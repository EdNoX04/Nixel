import Photos

/// Access check usable from non-UI contexts such as the background agent.
enum PhotoAccessHelper {
    static func current() -> PhotoAccess {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .full
        case .limited:       return .limited
        @unknown default:    return .denied
        }
    }
}
