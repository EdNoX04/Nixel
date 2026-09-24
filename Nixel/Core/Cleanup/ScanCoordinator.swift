import Foundation
import Photos
import SwiftUI

/// Owns the scan for every category and the results the UI reads.
///
/// Scanning runs off the main actor and reports progress back as it goes: on a real
/// library this takes long enough that a frozen screen would be unacceptable, and the
/// brief grades scan speed directly.
@Observable
@MainActor
final class ScanCoordinator {

    // MARK: Results

    var storage: StorageSnapshot = .empty
    var summaries: [CleanupCategory: CategorySummary] = [:]

    var similarGroups: [PhotoGroup] = []
    var screenshots: [PhotoAsset] = []
    var largeVideos: [PhotoAsset] = []
    var blurryPhotos: [PhotoAsset] = []
    var contactGroups: [ContactDuplicateGroup] = []
    var contactsScanned = 0
    /// How many photos in the library contain a person.
    var peopleCount = 0
    var contactError: String?

    /// Set when the library we scanned was only the subset a "limited access" user picked.
    var scannedLimitedLibrary = false

    private(set) var isScanning = false

    /// True once the user has asked for a scan themselves.
    ///
    /// Nothing is scanned until this is set. After that, reopening the app refreshes the
    /// results automatically — the person has already said yes, and asking again on every
    /// launch would be friction for no gain. Persisted, so it survives relaunches.
    var hasConsentedToScan: Bool {
        get { UserDefaults.standard.bool(forKey: "scan.consented") }
        set { UserDefaults.standard.set(newValue, forKey: "scan.consented") }
    }
    var lastScanDate: Date?
    var photosAnalysed = 0

    private let engine = SimilarityEngine()
    private let contactScanner = ContactScanner()
    let triage = ScreenshotTriage()
    let insights = PhotoInsight()

    /// AI-written descriptions of similar-photo groups, keyed by group id.
    var groupLabels: [String: String] = [:]
    private var scanTask: Task<Void, Never>?

    /// Verdicts from on-device intelligence, keyed by asset id.
    var screenshotVerdicts: [String: ScreenshotVerdict] = [:]
    private(set) var isTriaging = false

    init() {
        for category in CleanupCategory.allCases {
            summaries[category] = CategorySummary()
        }
        refreshStorage()
    }

    // MARK: Derived

    /// Overall scan progress, weighted by where the time actually goes.
    ///
    /// The old version averaged five categories equally. Screenshots and videos finish in
    /// a second, so it jumped straight to 40% and then sat there for the whole of the
    /// similar-photo pass — which is nearly all the work — looking hung. Categories that
    /// are not part of this scan (contacts without permission, say) are left out rather
    /// than counted as zero, which also stopped it topping out at 80%.
    var overallProgress: Double {
        let weights: [CleanupCategory: Double] = [
            .screenshots: 0.02, .largeVideos: 0.02, .similarPhotos: 0.90,
            .blurryPhotos: 0.03, .duplicateContacts: 0.03
        ]
        var done = 0.0, total = 0.0
        for (category, weight) in weights {
            guard let state = summaries[category]?.state else { continue }
            switch state {
            case .idle: continue
            case .blocked: continue
            case .scanning(let p): done += weight * p; total += weight
            case .ready: done += weight; total += weight
            }
        }
        guard total > 0 else { return isScanning ? progressFloor : 0 }
        let value = min(1, done / total)
        return isScanning ? max(progressFloor, value) : value
    }

    /// Where the ring stood when a scan was paused for the lock screen. A resumed scan
    /// re-runs its quick first steps, and without this the ring dipped back towards zero
    /// before catching up — which read as the scan starting over.
    private var progressFloor = 0.0
    private var pausedProgress = 0.0

    /// Total space the current findings could free.
    var totalReclaimable: Int64 {
        CleanupCategory.allCases
            .filter(\.measuresBytes)
            .reduce(0) { $0 + (summaries[$1]?.reclaimableBytes ?? 0) }
    }

    func summary(_ category: CleanupCategory) -> CategorySummary {
        summaries[category] ?? CategorySummary()
    }

    // MARK: Scanning

    // MARK: Contacts

    func scanContacts(access: ContactsAccess) {
        guard access.canScan else {
            summaries[.duplicateContacts]?.state = .blocked("Contacts access is off")
            return
        }
        summaries[.duplicateContacts]?.state = .scanning(0)
        contactError = nil

        Task { [contactScanner] in
            let records: [ContactRecord]
            do {
                records = try await contactScanner.fetchAll()
            } catch {
                self.summaries[.duplicateContacts]?.state = .blocked("Couldn't read contacts")
                self.contactError = error.localizedDescription
                return
            }
            let groups = await contactScanner.duplicateGroups(from: records)
            self.contactsScanned = records.count
            self.contactGroups = groups
            self.summaries[.duplicateContacts] = CategorySummary(
                state: .ready,
                itemCount: groups.reduce(0) { $0 + $1.others.count },
                reclaimableBytes: 0)
            self.writeContactDiagnostics()
        }
    }

    /// Counts only, like `scan-status.json` — lets the contact matcher be checked on a
    /// device without reading a single name.
    private func writeContactDiagnostics() {
        let status: [String: Any] = [
            "contactsVisible": contactsScanned,
            "contactGroups": contactGroups.count,
            "contactExtras": contactGroups.reduce(0) { $0 + $1.others.count },
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("contact-status.json")
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Drops assets that have just been deleted from the in-memory results, so the user
    /// never sees a thumbnail for something that is already gone. Cheaper and far less
    /// jarring than re-running the whole scan after every cleanup.
    /// Asks the on-device model what a group shows. Lazy and cached: called as groups
    /// scroll into view rather than for the whole library during the scan.
    func describeGroup(_ group: PhotoGroup) {
        guard groupLabels[group.id] == nil, !labelsInFlight.contains(group.id),
              IntelligenceService.shared.availability.isAvailable else { return }
        // Rows re-appear as the list scrolls; without this each appearance started another
        // image load and model request for the same group.
        labelsInFlight.insert(group.id)
        Task { [insights] in
            let insight = await insights.describe(group: group)
            await MainActor.run {
                self.labelsInFlight.remove(group.id)
                if let insight { self.groupLabels[group.id] = insight.label }
            }
        }
    }

    func removeDeleted(ids: Set<String>) {
        guard !ids.isEmpty else { return }

        screenshots.removeAll { ids.contains($0.id) }
        largeVideos.removeAll { ids.contains($0.id) }
        blurryPhotos.removeAll { ids.contains($0.id) }

        similarGroups = similarGroups.compactMap { group in
            var updated = group
            updated.assets.removeAll { ids.contains($0.id) }
            // A group with one photo left is no longer a duplicate group.
            guard updated.assets.count > 1 else { return nil }
            if ids.contains(updated.bestID) {
                updated.bestID = SimilarityEngine.pickBest(from: updated.assets)
            }
            return updated
        }

        for id in ids { screenshotVerdicts.removeValue(forKey: id) }

        recomputeSummaries()
    }

    /// Updates counts after a deletion. A category's state is left as it was: forcing
    /// everything to "ready" mid-scan made the progress ring jump.
    /// Videos at or above this size are "large": they count towards what can be freed.
    /// Every video is still listed, largest first; the small ones just aren't promised back.
    static let largeVideoBytes: Int64 = 20 * 1_000_000

    /// What the dashboard may honestly promise: screenshots the app itself holds back
    /// (receipts, tickets, codes) are never counted as space to free.
    private var freeableScreenshots: [PhotoAsset] {
        screenshots.filter { asset in
            guard let verdict = screenshotVerdicts[asset.id] else { return true }
            return verdict.safeToDelete || !verdict.kind.isSensitive
        }
    }

    private var freeableVideos: [PhotoAsset] {
        largeVideos.filter { $0.bytes >= Self.largeVideoBytes }
    }

    private func recomputeSummaries() {
        func update(_ category: CleanupCategory, count: Int, bytes: Int64) {
            let state = summaries[category]?.state ?? .ready
            summaries[category] = CategorySummary(state: state, itemCount: count,
                                                  reclaimableBytes: bytes)
        }
        update(.screenshots, count: freeableScreenshots.count,
               bytes: freeableScreenshots.reduce(0) { $0 + $1.bytes })
        update(.largeVideos, count: freeableVideos.count,
               bytes: freeableVideos.reduce(0) { $0 + $1.bytes })
        update(.blurryPhotos, count: blurryPhotos.count,
               bytes: blurryPhotos.reduce(0) { $0 + $1.bytes })
        update(.similarPhotos, count: similarGroups.reduce(0) { $0 + $1.others.count },
               bytes: similarGroups.reduce(0) { $0 + $1.reclaimableBytes })
    }

    func removeContactGroup(_ id: String) {
        contactGroups.removeAll { $0.id == id }
        summaries[.duplicateContacts] = CategorySummary(
            state: .ready,
            itemCount: contactGroups.reduce(0) { $0 + $1.others.count },
            reclaimableBytes: 0)
    }

    /// Counts only — what the scan could see, never what it saw.
    ///
    /// Written after every scan so behaviour on a real device can be checked from a Mac
    /// without looking at anyone's photos: how many assets were visible, under which access
    /// level, which descriptor engine ran, and how long it took.
    private func writeDiagnostics(access: PhotoAccess, duration: TimeInterval) {
        let status: [String: Any] = [
            "access": "\(access)",
            "photosVisible": photosAnalysed,
            "screenshotsVisible": screenshots.count,
            "videosVisible": largeVideos.count,
            "similarGroups": similarGroups.count,
            "similarExtras": similarGroups.reduce(0) { $0 + $1.others.count },
            "blurry": blurryPhotos.count,
            "peopleDetectionAvailable": PeopleDetector.isAvailable,
            "photosWithPeople": peopleCount,
            "engine": "\(DescriptorEngine.expectedKind)",
            "durationSeconds": (duration * 10).rounded() / 10,
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan-status.json")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: status, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Clears every result held in memory. Used by the debug reset, and harmless to call.
    func resetResults() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        lastScanDate = nil
        photosAnalysed = 0
        similarGroups = []
        screenshots = []
        largeVideos = []
        blurryPhotos = []
        contactGroups = []
        screenshotVerdicts = [:]
        groupLabels = [:]
        peopleCount = 0
        for category in CleanupCategory.allCases { summaries[category] = CategorySummary() }
    }

    /// Reads volume capacity off the main thread.
    ///
    /// "Available for important usage" makes iOS work out how much it could purge, which is
    /// instant in the Simulator and can take seconds on a real phone. It used to run on the
    /// main thread at launch and every time the app came back to the foreground — so waking
    /// the phone froze the UI while iOS did its sums.
    func refreshStorage() {
        trace("storage: refresh requested")
        Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                DeviceStorage.snapshot()
            }.value
            self?.storage = snapshot
            trace("storage: refreshed")
        }
    }

    private var resumeAfterBackground = false

    /// Incremented for every scan started; a scan only writes results while it is current.
    private var scanGeneration = 0

    /// The phone is locking or the app is leaving the screen.
    ///
    /// iOS suspends the process shortly after this, and a scan left running across that
    /// suspension resumes with Vision and model requests half-finished on the neural
    /// engine — the state behind "the app hangs after the phone locks". So stop cleanly
    /// instead: the descriptor cache is saved on cancellation, and every photo already
    /// analysed is skipped when the scan picks up again.
    func handleBackground() {
        // Screenshot triage runs OCR and the on-device model — neither belongs in the
        // background. Anything unfinished is picked up by the next scan.
        if isTriaging {
            triageTask?.cancel()
            isTriaging = false
            triageInterrupted = !isScanning     // a paused scan restarts triage itself
        }
        guard isScanning else { return }
        trace("background: pausing scan")
        resumeAfterBackground = true
        pausedProgress = overallProgress
        cancelScan()
    }

    func handleForeground(access: PhotoAccess) {
        refreshStorage()
        if triageInterrupted {
            triageInterrupted = false
            startTriage(screenshots)
        }
        guard resumeAfterBackground else { return }
        resumeAfterBackground = false
        trace("foreground: resuming scan")
        scanPhotos(access: access, restart: true)
        progressFloor = pausedProgress
    }

    /// Set by the Stop button, so an automatic rescan (a view reappearing, a palette
    /// rebuild) doesn't quietly undo it. Cleared by the next scan the user asks for.
    private(set) var stoppedByUser = false

    func resumeAfterStop() { stoppedByUser = false }

    func stopScan() {
        stoppedByUser = true
        resumeAfterBackground = false
        cancelScan()
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        for category in CleanupCategory.allCases where summaries[category]?.state.isScanning == true {
            summaries[category]?.state = .idle
        }
    }

    /// Starts a scan. A request that arrives while one is already running is ignored unless
    /// `restart` is set: returning to the storage tab re-runs its `.task`, and that used to
    /// cancel the scan in progress and start over from 0% on every visit.
    func scanPhotos(access: PhotoAccess, restart: Bool = false) {
        if isScanning && !restart {
            trace("scan request ignored: already scanning")
            return
        }
        progressFloor = 0
        guard access.canScan else {
            let reason = access == .denied || access == .restricted
                ? "Photo access is off"
                : "Photo access needed"
            for category in photoCategories { summaries[category]?.state = .blocked(reason) }
            return
        }

        scanTask?.cancel()
        scanGeneration += 1
        let generation = scanGeneration
        isScanning = true
        scannedLimitedLibrary = (access == .limited)
        for category in photoCategories { summaries[category]?.state = .scanning(0) }

        let started = Date()
        trace("scan requested, access=\(access)")
        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.runPhotoScan()

            // A scan with nothing to read finishes in milliseconds, which flicked the UI
            // into the scanning state and straight back out. Hold it long enough to read as
            // a deliberate beat rather than a glitch.
            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 1.4 {
                try? await Task.sleep(nanoseconds: UInt64((1.4 - elapsed) * 1_000_000_000))
            }

            // A cancelled or superseded scan must not write anything. It used to: a scan
            // cancelled when the phone locked finished later, once its Vision calls came
            // back, and set "not scanning" over the top of the scan that replaced it —
            // leaving a Stop button beside a finished headline.
            guard !Task.isCancelled, generation == self.scanGeneration else {
                trace("scan: superseded, discarding results")
                return
            }

            trace("scan: finished in \(String(format: "%.1f", elapsed))s")
            self.isScanning = false
            self.progressFloor = 0
            self.lastScanDate = Date()
            self.refreshStorage()
            self.writeDiagnostics(access: access, duration: elapsed)
        }
    }

    private var photoCategories: [CleanupCategory] {
        [.similarPhotos, .screenshots, .largeVideos, .blurryPhotos]
    }

    /// Classifies screenshots once the heavy pass has finished. Fire-and-forget: the grid is
    /// already on screen, and categories fill in as they are decided.
    private var triageTask: Task<Void, Never>?
    private var triageInterrupted = false
    private var labelsInFlight: Set<String> = []

    /// One triage at a time, owned here so it can be stopped. It used to be a free-running
    /// task: every rescan started another, and it kept running OCR and the model after
    /// the app went to the background.
    private func startTriage(_ assets: [PhotoAsset]) {
        triageTask?.cancel()
        guard !assets.isEmpty else { return }
        triageTask = Task { [weak self, triage] in
            let ready = await IntelligenceService.shared.currentAvailability().isAvailable
            trace("triage: intelligence available=\(ready)")
            guard ready else { return }
            await MainActor.run { self?.isTriaging = true }
            await triage.triage(assets) { _ in }
            guard !Task.isCancelled else {
                await MainActor.run { self?.isTriaging = false }
                return
            }
            let verdicts = await triage.allVerdicts()
            await MainActor.run {
                self?.screenshotVerdicts = verdicts
                self?.isTriaging = false
                // Receipts and tickets now known: take them out of "can be freed".
                self?.recomputeSummaries()
                trace("triage: done, \(verdicts.count) verdicts")
            }
        }
    }

    /// Entry point for the background agent: runs the same scan, then waits for it.
    func scanForAgent() async {
        guard PhotoAccessHelper.current().canScan else { return }
        await runPhotoScan()
    }

    private func runPhotoScan() async {
        trace("runPhotoScan: start")
        // --- 1. Screenshots and videos: cheap, metadata-driven, show them first. ---
        trace("screenshots: fetching")
        let screenshotAssets = await Task.detached(priority: .userInitiated) {
            PhotoFetch.screenshots()
        }.value
        trace("screenshots: fetched \(screenshotAssets.count), sizing")

        let sized = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            zip(screenshotAssets, AssetSize.bytes(for: screenshotAssets)).map { asset, bytes in
                var item = PhotoAsset(asset)
                item.bytes = bytes
                return item
            }
        }.value

        trace("screenshots: sized")
        guard !Task.isCancelled else { return }
        screenshots = sized
        summaries[.screenshots] = CategorySummary(
            state: .ready,
            itemCount: freeableScreenshots.count,
            reclaimableBytes: freeableScreenshots.reduce(0) { $0 + $1.bytes })

        // Screenshot triage (OCR and the language model) is deliberately NOT started here.
        // It used to launch alongside the similarity pass, so three neural workloads cold-
        // started on the Neural Engine at the same instant. It now runs once that pass is
        // done — see the end of this function.
        let screenshotsToTriage = sized

        trace("videos: fetching + sizing")
        let videoAssets = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            let videos = PhotoFetch.videos()
            return zip(videos, AssetSize.bytes(for: videos))
                .map { asset, bytes in
                    var item = PhotoAsset(asset)
                    item.bytes = bytes
                    return item
                }
                .sorted { $0.bytes > $1.bytes }
        }.value

        guard !Task.isCancelled else { return }
        largeVideos = videoAssets
        summaries[.largeVideos] = CategorySummary(
            state: .ready,
            itemCount: freeableVideos.count,
            reclaimableBytes: freeableVideos.reduce(0) { $0 + $1.bytes })

        // --- 2. Similar photos: the expensive pass. ---
        trace("videos: done \(largeVideos.count); photos: fetching")
        let photoAssets = await Task.detached(priority: .userInitiated) {
            PhotoFetch.allPhotos().map(PhotoAsset.init)
        }.value
        trace("photos: fetched \(photoAssets.count)")

        guard !Task.isCancelled else { return }
        photosAnalysed = photoAssets.count

        let generation = scanGeneration
        await engine.prepare(photoAssets) { [weak self] fraction in
            Task { @MainActor in
                // A stopped or superseded scan must not leave the ring showing "scanning".
                guard let self, generation == self.scanGeneration, self.isScanning else { return }
                self.summaries[.similarPhotos]?.state = .scanning(fraction)
            }
        }

        guard !Task.isCancelled else { return }

        trace("prepare: done; grouping")
        // Screenshots have their own tab; grouping them too would put the same item in two
        // bulk selections, and a group's keeper could go out through the other one.
        let screenshotIDs = Set(screenshotsToTriage.map(\.id))
        var groups = await engine.group(photoAssets.filter { !screenshotIDs.contains($0.id) })
        trace("group: \(groups.count) groups")

        // Resolve byte sizes only for photos inside a group — that is the only place the
        // number is shown, and it saves thousands of resource lookups on a big library.
        groups = await Task.detached(priority: .userInitiated) { () -> [PhotoGroup] in
            var sizes = AssetSize.bytes(for: groups.flatMap { $0.assets.map(\.phAsset) })[...]
            return groups.map { group in
                var updated = group
                let groupSizes = sizes.prefix(group.assets.count)
                sizes = sizes.dropFirst(group.assets.count)
                updated.assets = zip(group.assets, groupSizes).map { asset, bytes in
                    var item = asset
                    item.bytes = bytes
                    return item
                }
                return updated
            }
            .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        }.value

        guard !Task.isCancelled else { return }
        similarGroups = groups
        summaries[.similarPhotos] = CategorySummary(
            state: .ready,
            itemCount: groups.reduce(0) { $0 + $1.others.count },
            reclaimableBytes: groups.reduce(0) { $0 + $1.reclaimableBytes })

        trace("sizing grouped photos: done")
        // --- 3. People, then blurry. ---
        let people = await engine.peopleCounts(for: photoAssets)
        screenshots = screenshots.map { var a = $0; a.peopleCount = people[$0.id]; return a }
        similarGroups = similarGroups.map { group in
            var updated = group
            updated.assets = group.assets.map { var a = $0; a.peopleCount = people[$0.id]; return a }
            return updated
        }
        peopleCount = people.values.filter { $0 > 0 }.count

        let scores = await engine.sharpnessScores(for: photoAssets)
        let scored = photoAssets.map { asset -> PhotoAsset in
            var item = asset
            item.sharpness = scores[asset.id]
            item.peopleCount = people[asset.id]
            return item
        }

        // Every photo in a similar group stays out of Blurry — the extras so the same bytes
        // aren't promised twice, and the keeper so a Select All here plus one on the group
        // can never delete the whole group between them.
        let claimed = Set(groups.flatMap { $0.assets.map(\.id) })
        // Screenshots found by screen resolution alone aren't flagged as screenshots by
        // Photos, so exclude them by id — they belong to the Screenshots tab only.
        let detected = BlurDetector.detect(in: scored.filter {
            !claimed.contains($0.id) && !screenshotIDs.contains($0.id)
        })

        let blurrySized = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            zip(detected, AssetSize.bytes(for: detected.map(\.phAsset))).map { asset, bytes in
                var item = asset
                item.bytes = bytes
                return item
            }
        }.value

        trace("blurry: \(blurrySized.count)")
        Task.detached(priority: .utility) { AssetSize.persist() }
        guard !Task.isCancelled else { return }
        blurryPhotos = blurrySized
        summaries[.blurryPhotos] = CategorySummary(
            state: .ready,
            itemCount: blurrySized.count,
            reclaimableBytes: blurrySized.reduce(0) { $0 + $1.bytes })

        startTriage(screenshotsToTriage)
    }
}
