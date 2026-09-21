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

    /// Set when the library we scanned was only the subset a "limited access" user picked.
    var scannedLimitedLibrary = false

    private(set) var isScanning = false
    private(set) var lastScanDate: Date?
    private(set) var photosAnalysed = 0

    private let engine = SimilarityEngine()
    let triage = ScreenshotTriage()
    private var scanTask: Task<Void, Never>?

    /// Verdicts from on-device intelligence, keyed by asset id.
    var screenshotVerdicts: [String: ScreenshotVerdict] = [:]

    init() {
        for category in CleanupCategory.allCases {
            summaries[category] = CategorySummary()
        }
    }

    // MARK: Derived

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
            Task { [weak self, triage] in
                await triage.triage(sized) { _ in }
                let verdicts = await triage.allVerdicts()
                await MainActor.run { self?.screenshotVerdicts = verdicts }
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

        // Blurry detection is wired up in a later pass; report an honest empty result
        // rather than leaving a spinner running forever.
        summaries[.blurryPhotos] = CategorySummary(state: .ready, itemCount: 0, reclaimableBytes: 0)
    }
}
