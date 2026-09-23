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

    /// Focus score, 0...1, higher is sharper. `nil` until measured.
    var sharpness: Double?

    /// How many people Vision found. `nil` until measured, 0 means none were found.
    var peopleCount: Int?

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

    // Equality is synthesised over every field, so SwiftUI redraws when a size or people
    // count changes. It used to compare ids only, and an updated asset could be treated as
    // unchanged — a stale people count then slipped past the Select All brake.
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

    /// Sizes many assets at once. Each lookup is a Photos database round trip of ~10 ms
    /// and they are independent, so they are spread across cores: 225 grouped photos went
    /// from 2.6 s to a fraction of that on an iPhone 15 Pro Max.
    static func bytes(for assets: [PHAsset]) -> [Int64] {
        var sizes = [Int64](repeating: 0, count: assets.count)
        sizes.withUnsafeMutableBufferPointer { buffer in
            DispatchQueue.concurrentPerform(iterations: assets.count) { index in
                buffer[index] = bytes(for: assets[index])
            }
        }
        return sizes
    }

    static func bytes(for asset: PHAsset) -> Int64 {
        // A resource's size only changes with an edit, which bumps the modification date.
        let key = "\(asset.localIdentifier)|\(asset.modificationDate?.timeIntervalSince1970 ?? 0)"
        if let known = cache.value(for: key) { return known }
        let size = measure(asset)
        cache.set(size, for: key)
        return size
    }

    private static let cache = SizeCache()

    /// Writes the size cache to disk. Sizes only change with an edit, and the lookups
    /// don't parallelise well (Photos serialises them), so a rescan that reuses them
    /// skips the slowest step of the scan outright.
    static func persist() { cache.save() }

    private static func measure(_ asset: PHAsset) -> Int64 {
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
        // `value(forKey:)` on a key that doesn't exist raises an Objective-C exception
        // Swift can't catch, so check the key is there before asking for it.
        if resource.responds(to: NSSelectorFromString("fileSize")),
           let number = resource.value(forKey: "fileSize") as? NSNumber {
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

/// Asset sizes keyed by identifier and modification date, kept across launches.
private final class SizeCache: @unchecked Sendable {
    static let fileName = "asset-sizes.json"

    private let lock = NSLock()
    private var sizes: [String: Int64]
    private var dirty = false

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    init() {
        sizes = (try? Data(contentsOf: Self.url))
            .flatMap { try? JSONDecoder().decode([String: Int64].self, from: $0) } ?? [:]
    }

    func value(for key: String) -> Int64? { lock.lock(); defer { lock.unlock() }; return sizes[key] }

    func set(_ size: Int64, for key: String) {
        lock.lock(); sizes[key] = size; dirty = true; lock.unlock()
    }

    func save() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        let snapshot = sizes
        dirty = false
        lock.unlock()
        try? FileManager.default.createDirectory(
            at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: Self.url, options: .atomic)
            Self.url.excludeFromBackup()
        }
    }
}
