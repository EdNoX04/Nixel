import Foundation
import Photos
import UIKit

/// Thin wrappers around `PHAsset` fetches.
///
/// Fetches here return metadata only — no image data is decoded — so even a 50,000 asset
/// library comes back in well under a second. The expensive work happens later, and only
/// on the assets we actually need.
enum PhotoFetch {

    static func allPhotos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeHiddenAssets = false
        return collect(PHAsset.fetchAssets(with: options))
    }

    /// Screenshots.
    ///
    /// The primary signal is the system's own flag — either the Screenshots smart album or
    /// `PHAssetMediaSubtype.photoScreenshot`. That flag is set at capture time and is what
    /// the user already sees in Photos, so it is what we trust first.
    ///
    /// A secondary signal catches screenshots that *lost* the flag: anything AirDropped,
    /// sent through a messaging app and re-saved, or restored from a backup comes back as
    /// an ordinary photo. Those are still screenshots to the user and still worth
    /// reclaiming. We identify them by an exact match against this device's native screen
    /// resolution, which is deliberately strict — a camera photo never lands on exactly
    /// those dimensions, because sensor aspect ratios don't match the display's.
    static func screenshots() -> [PHAsset] {
        var found: [PHAsset] = []
        var seen = Set<String>()

        func add(_ assets: [PHAsset]) {
            for asset in assets where !seen.contains(asset.localIdentifier) {
                seen.insert(asset.localIdentifier)
                found.append(asset)
            }
        }

        // 1. The system smart album.
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        if let album = albums.firstObject {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            add(collect(PHAsset.fetchAssets(in: album, options: options)))
        }

        // 2. The media-subtype flag, in case the album is unavailable.
        let flagged = PHFetchOptions()
        flagged.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue)
        flagged.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        add(collect(PHAsset.fetchAssets(with: flagged)))

        // 3. Exact native-resolution matches that the flag missed.
        add(nativeSizedImages().filter { !seen.contains($0.localIdentifier) })

        return found.sorted {
            ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast)
        }
    }

    /// Images whose pixel dimensions exactly equal this device's screen, in either
    /// orientation. Queried in the fetch predicate so we never enumerate the whole library.
    private static func nativeSizedImages() -> [PHAsset] {
        let native = UIScreen.main.nativeBounds.size
        let width = Int(native.width), height = Int(native.height)
        guard width > 0, height > 0 else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: """
            mediaType == %d AND             ((pixelWidth == %d AND pixelHeight == %d) OR (pixelWidth == %d AND pixelHeight == %d))
            """,
            PHAssetMediaType.image.rawValue,
            width, height, height, width)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return collect(PHAsset.fetchAssets(with: options))
    }

    static func videos() -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.includeHiddenAssets = false
        return collect(PHAsset.fetchAssets(with: options))
    }

    private static func collect(_ result: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }
}
