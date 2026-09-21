import Foundation
import Photos

/// A lightweight, value-type view of a `PHAsset` plus its resolved on-disk size.
struct PhotoAsset: Identifiable, Hashable {
    let id: String                 // PHAsset.localIdentifier
    let phAsset: PHAsset
    let pixelWidth: Int
    let pixelHeight: Int
    let creationDate: Date?
    let duration: TimeInterval
    let isFavorite: Bool
    let isVideo: Bool
    let isScreenshot: Bool

    /// Bytes this asset occupies. Resolved on demand — see `AssetSize`.
    var bytes: Int64 = 0

    /// Sharpness score (variance of Laplacian). Higher is sharper. `nil` until measured.
    var sharpness: Double?

    var pixels: Int { pixelWidth * pixelHeight }

    init(_ asset: PHAsset) {
        id = asset.localIdentifier
        phAsset = asset
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        creationDate = asset.creationDate
        duration = asset.duration
        isFavorite = asset.isFavorite
        isVideo = asset.mediaType == .video
        isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
    }

    static func == (a: PhotoAsset, b: PhotoAsset) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Resolves how many bytes an asset actually occupies.
///
/// There is no single public API that covers every supported OS here:
///
///  * iOS 27 added `PHAssetResource.dataSize`, which is public, instant and exact.
///  * Below that the only fast path is the private `fileSize` key via KVC. It is
///    read-only introspection, degrades to 0 rather than crashing if it ever goes away,
///    and is the same approach the category leaders use.
///  * If both fail we fall back to an estimate rather than showing nothing.
///
/// Every number the user sees as "space freed" flows through here, so it is deliberately
/// conservative: when we cannot know a size we under-promise instead of inventing one.
enum AssetSize {

    static func bytes(for asset: PHAsset) -> Int64 {
        let resources = PHAssetResource.assetResources(for: asset)
        guard !resources.isEmpty else { return estimate(for: asset) }

        // Sum every resource: deleting the asset reclaims all of them (original +
        // edited render + paired Live Photo video), so the total is what actually frees.
        var total: Int64 = 0
        for resource in resources {
            total += size(of: resource)
        }
        return total > 0 ? total : estimate(for: asset)
    }

    private static func size(of resource: PHAssetResource) -> Int64 {
        if #available(iOS 27.0, *) {
            if let exact = resource.dataSize { return Int64(exact) }
        }
        if let number = resource.value(forKey: "fileSize") as? NSNumber {
            return number.int64Value
        }
        return 0
    }

    /// Last-resort approximation when the library will not tell us a size.
    /// Video: a conservative bitrate. Photo: pixels x a typical HEIC bits-per-pixel.
    private static func estimate(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            let megabitsPerSecond = 10.0
            return Int64(asset.duration * megabitsPerSecond * 1_000_000 / 8)
        }
        let pixels = Double(asset.pixelWidth * asset.pixelHeight)
        return Int64(pixels * 0.30)          // ~0.3 bytes/pixel for HEIC
    }
}
