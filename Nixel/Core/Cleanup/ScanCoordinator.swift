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

    var storage: StorageSnapshot = DeviceStorage.snapshot()
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
            .screenshots: 0.05, .largeVideos: 0.05, .similarPhotos: 0.80,
            .blurryPhotos: 0.05, .duplicateContacts: 0.05
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
        guard total > 0 else { return 0 }
        return min(1, done / total)
    }

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
        }
    }

    /// Drops assets that have just been deleted from the in-memory results, so the user
    /// never sees a thumbnail for something that is already gone. Cheaper and far less
    /// jarring than re-running the whole scan after every cleanup.
    /// Asks the on-device model what a group shows. Lazy and cached: called as groups
    /// scroll into view rather than for the whole library during the scan.
    func describeGroup(_ group: PhotoGroup) {
        guard groupLabels[group.id] == nil,
              IntelligenceService.shared.availability.isAvailable else { return }
        Task { [insights] in
            if let insight = await insights.describe(group: group) {
                await MainActor.run { self.groupLabels[group.id] = insight.label }
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

    private func recomputeSummaries() {
        summaries[.screenshots] = CategorySummary(
            state: .ready, itemCount: screenshots.count,
            reclaimableBytes: screenshots.reduce(0) { $0 + $1.bytes })
        summaries[.largeVideos] = CategorySummary(
            state: .ready, itemCount: largeVideos.count,
            reclaimableBytes: largeVideos.reduce(0) { $0 + $1.bytes })
        summaries[.blurryPhotos] = CategorySummary(
            state: .ready, itemCount: blurryPhotos.count,
            reclaimableBytes: blurryPhotos.reduce(0) { $0 + $1.bytes })
        summaries[.similarPhotos] = CategorySummary(
            state: .ready,
            itemCount: similarGroups.reduce(0) { $0 + $1.others.count },
            reclaimableBytes: similarGroups.reduce(0) { $0 + $1.reclaimableBytes })
    }

    func removeContactGroup(_ id: String) {
        contactGroups.removeAll { $0.id == id }
        summaries[.duplicateContacts] = CategorySummary(
            state: .ready,
            itemCount: contactGroups.reduce(0) { $0 + $1.others.count },
            reclaimableBytes: 0)
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

    func refreshStorage() {
        storage = DeviceStorage.snapshot()
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
        for category in CleanupCategory.allCases where summaries[category]?.state.isScanning == true {
            summaries[category]?.state = .idle
        }
    }

    func scanPhotos(access: PhotoAccess) {
        guard access.canScan else {
            let reason = access == .denied || access == .restricted
                ? "Photo access is off"
                : "Photo access needed"
            for category in photoCategories { summaries[category]?.state = .blocked(reason) }
            return
        }

        scanTask?.cancel()
        isScanning = true
        scannedLimitedLibrary = (access == .limited)
        for category in photoCategories { summaries[category]?.state = .scanning(0) }

        scanTask = Task { [weak self] in
            guard let self else { return }
            await self.runPhotoScan()
            self.isScanning = false
            self.lastScanDate = Date()
            self.refreshStorage()
        }
    }

    private var photoCategories: [CleanupCategory] {
        [.similarPhotos, .screenshots, .largeVideos, .blurryPhotos]
    }

    /// Entry point for the background agent: runs the same scan, then waits for it.
    func scanForAgent() async {
        guard PhotoAccessHelper.current().canScan else { return }
        await runPhotoScan()
    }

    private func runPhotoScan() async {
        // --- 1. Screenshots and videos: cheap, metadata-driven, show them first. ---
        let screenshotAssets = await Task.detached(priority: .userInitiated) {
            PhotoFetch.screenshots()
        }.value

        let sized = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            screenshotAssets.map { asset in
                var item = PhotoAsset(asset)
                item.bytes = AssetSize.bytes(for: asset)
                return item
            }
        }.value

        guard !Task.isCancelled else { return }
        screenshots = sized
        summaries[.screenshots] = CategorySummary(
            state: .ready,
            itemCount: sized.count,
            reclaimableBytes: sized.reduce(0) { $0 + $1.bytes })

        // On-device triage of screenshots. Runs after the list is already on screen so
        // the user never waits on the model to see their screenshots.
        if IntelligenceService.shared.availability.isAvailable, !sized.isEmpty {
            isTriaging = true
            Task { [weak self, triage] in
                await triage.triage(sized) { _ in }
                let verdicts = await triage.allVerdicts()
                await MainActor.run {
                    self?.screenshotVerdicts = verdicts
                    self?.isTriaging = false
                }
            }
        }

        let videoAssets = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            PhotoFetch.videos()
                .map { asset in
                    var item = PhotoAsset(asset)
                    item.bytes = AssetSize.bytes(for: asset)
                    return item
                }
                .sorted { $0.bytes > $1.bytes }
        }.value

        guard !Task.isCancelled else { return }
        largeVideos = videoAssets
        summaries[.largeVideos] = CategorySummary(
            state: .ready,
            itemCount: videoAssets.count,
            reclaimableBytes: videoAssets.reduce(0) { $0 + $1.bytes })

        // --- 2. Similar photos: the expensive pass. ---
        let photoAssets = await Task.detached(priority: .userInitiated) {
            PhotoFetch.allPhotos().map(PhotoAsset.init)
        }.value

        guard !Task.isCancelled else { return }
        photosAnalysed = photoAssets.count

        await engine.prepare(photoAssets) { [weak self] fraction in
            Task { @MainActor in
                self?.summaries[.similarPhotos]?.state = .scanning(fraction)
            }
        }

        guard !Task.isCancelled else { return }

        var groups = await engine.group(photoAssets)

        // Resolve byte sizes only for photos inside a group — that is the only place the
        // number is shown, and it saves thousands of resource lookups on a big library.
        groups = await Task.detached(priority: .userInitiated) { () -> [PhotoGroup] in
            groups.map { group in
                var updated = group
                updated.assets = group.assets.map { asset in
                    var item = asset
                    item.bytes = AssetSize.bytes(for: asset.phAsset)
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

        // Photos already queued for removal as duplicates should not also be counted here,
        // or the dashboard would promise the same bytes back twice.
        let claimed = Set(groups.flatMap { $0.others.map(\.id) })
        let detected = BlurDetector.detect(in: scored.filter { !claimed.contains($0.id) })

        let blurrySized = await Task.detached(priority: .userInitiated) { () -> [PhotoAsset] in
            detected.map { asset in
                var item = asset
                item.bytes = AssetSize.bytes(for: asset.phAsset)
                return item
            }
        }.value

        guard !Task.isCancelled else { return }
        blurryPhotos = blurrySized
        summaries[.blurryPhotos] = CategorySummary(
            state: .ready,
            itemCount: blurrySized.count,
            reclaimableBytes: blurrySized.reduce(0) { $0 + $1.bytes })
    }
}
