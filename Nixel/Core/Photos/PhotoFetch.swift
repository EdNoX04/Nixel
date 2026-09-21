import Foundation
import Photos

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

    /// Screenshots, preferring the system smart album so our list matches what the user
    /// already sees in Photos. Falls back to the media-subtype flag if the album is missing.
    static func screenshots() -> [PHAsset] {
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)

        if let album = albums.firstObject {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            let assets = collect(PHAsset.fetchAssets(in: album, options: options))
            if !assets.isEmpty { return assets }
        }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND (mediaSubtypes & %d) != 0",
            PHAssetMediaType.image.rawValue,
            PHAssetMediaSubtype.photoScreenshot.rawValue)
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
