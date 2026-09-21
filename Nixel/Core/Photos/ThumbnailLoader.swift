import UIKit
import Photos

/// Loads images out of the photo library.
///
/// Two rules matter here:
///
///  * `isNetworkAccessAllowed = false` for scanning. If the user has "Optimize iPhone
///    Storage" on, full-quality originals live in iCloud; requesting them would download
///    gigabytes over cellular during a scan. We analyse the local thumbnail instead.
///  * `.fastFormat` + `.fast` resize. We are feeding a 224pt perceptual model, not showing
///    the picture — exact colour fidelity buys nothing and costs a lot of time.
actor ThumbnailLoader {

    static let shared = ThumbnailLoader()

    private let manager = PHCachingImageManager()

    /// Small square image used for perceptual hashing / sharpness. Local-only.
    func analysisImage(for asset: PHAsset, side: CGFloat = 224) -> UIImage? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true          // we are already off the main actor
        options.version = .current

        var result: UIImage?
        manager.requestImage(
            for: asset,
            targetSize: CGSize(width: side, height: side),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            result = image
        }
        return result
    }
}

/// Display-quality thumbnails for grids, kept separate from the analysis path because
/// these *may* hit the network (a placeholder-only asset should still render for the user).
@MainActor
final class GridThumbnailProvider {
    static let shared = GridThumbnailProvider()

    private let manager = PHCachingImageManager()
    private var inFlight: [String: PHImageRequestID] = [:]

    func image(for asset: PHAsset, side: CGFloat, completion: @escaping (UIImage?) -> Void) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let scale = UIScreen.main.scale
        return manager.requestImage(
            for: asset,
            targetSize: CGSize(width: side * scale, height: side * scale),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            completion(image)
        }
    }

    func cancel(_ id: PHImageRequestID) {
        manager.cancelImageRequest(id)
    }

    func startCaching(_ assets: [PHAsset], side: CGFloat) {
        let scale = UIScreen.main.scale
        manager.startCachingImages(for: assets,
                                   targetSize: CGSize(width: side * scale, height: side * scale),
                                   contentMode: .aspectFill, options: nil)
    }

    func stopCachingAll() { manager.stopCachingImagesForAllAssets() }
}
