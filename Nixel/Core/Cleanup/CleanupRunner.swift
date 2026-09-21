import Foundation
import Photos

/// The only code in Nixel that removes anything.
///
/// Deletion goes through `PHAssetChangeRequest.deleteAssets`, which makes iOS present its
/// own confirmation sheet. That is deliberate — it means there are two independent gates
/// before a photo goes anywhere: our review screen, and the system's own prompt. If the
/// user backs out of the system sheet, Photos reports `userCancelled` and we treat that as
/// a first-class outcome rather than an error.
@Observable
@MainActor
final class CleanupRunner {

    enum Outcome: Equatable {
        case idle
        case running
        case finished(removed: Int, bytes: Int64)
        case cancelled
        case failed(String)
    }

    private(set) var outcome: Outcome = .idle

    var isRunning: Bool { outcome == .running }

    func reset() { outcome = .idle }

    /// Deletes the given assets. Returns the ids that actually went away.
    @discardableResult
    func delete(_ assets: [PhotoAsset]) async -> Set<String> {
        guard !assets.isEmpty else { return [] }

        outcome = .running
        let bytes = assets.reduce(Int64(0)) { $0 + $1.bytes }
        let phAssets = assets.map(\.phAsset)

        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(phAssets as NSArray)
            }
            outcome = .finished(removed: assets.count, bytes: bytes)
            return Set(assets.map(\.id))
        } catch {
            if Self.isUserCancellation(error) {
                outcome = .cancelled
            } else {
                outcome = .failed(error.localizedDescription)
            }
            return []
        }
    }

    /// Photos reports a declined system prompt as a cancellation, not a failure.
    /// We match on the Photos error domain and fall back to Foundation's cancel code.
    private static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == PHPhotosErrorDomain,
           nsError.code == PHPhotosError.userCancelled.rawValue {
            return true
        }
        return nsError.code == NSUserCancelledError
    }
}
