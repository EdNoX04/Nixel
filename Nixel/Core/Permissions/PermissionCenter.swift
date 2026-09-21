import Foundation
import Photos
import Contacts
import PhotosUI
import UIKit

/// How much of the photo library we are allowed to see.
enum PhotoAccess: Equatable {
    case notDetermined
    case denied
    case restricted
    case limited        // user hand-picked a subset of photos
    case full

    var canScan: Bool { self == .full || self == .limited }
}

enum ContactsAccess: Equatable {
    case notDetermined
    case denied
    case restricted
    case limited        // iOS 18+
    case full

    var canScan: Bool { self == .full || self == .limited }
}

/// Owns every permission the app needs.
///
/// The brief calls out "denied" and "limited" explicitly, so both are first-class states
/// here rather than an afterthought: `limited` is a perfectly workable mode (we scan the
/// subset the user picked and say so), and `denied` never leaves the user stuck — every
/// blocked screen offers a route into Settings.
@Observable
@MainActor
final class PermissionCenter {

    private(set) var photos: PhotoAccess = .notDetermined
    private(set) var contacts: ContactsAccess = .notDetermined

    init() {
        refresh()
    }

    func refresh() {
        photos = Self.mapPhotos(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        contacts = Self.mapContacts(CNContactStore.authorizationStatus(for: .contacts))
    }

    // MARK: Requesting

    @discardableResult
    func requestPhotos() async -> PhotoAccess {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        photos = Self.mapPhotos(status)
        return photos
    }

    @discardableResult
    func requestContacts() async -> ContactsAccess {
        let store = CNContactStore()
        _ = try? await store.requestAccess(for: .contacts)
        contacts = Self.mapContacts(CNContactStore.authorizationStatus(for: .contacts))
        return contacts
    }

    /// Let a "limited access" user change which photos we can see.
    /// We suppress iOS's own periodic prompt via `PHPhotoLibraryPreventAutomaticLimitedAccessAlert`
    /// in Info.plist, so this is the one place that picker is offered — on purpose, not at random.
    func presentLimitedPicker(from controller: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Mapping

    private static func mapPhotos(_ s: PHAuthorizationStatus) -> PhotoAccess {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .full
        case .limited:       return .limited
        @unknown default:    return .denied
        }
    }

    private static func mapContacts(_ s: CNAuthorizationStatus) -> ContactsAccess {
        switch s {
        case .notDetermined: return .notDetermined
        case .restricted:    return .restricted
        case .denied:        return .denied
        case .authorized:    return .full
        default:
            // `.limited` is iOS 18+; compare by raw value so this still compiles and
            // behaves correctly on the iOS 17 deployment target.
            if #available(iOS 18.0, *), s == .limited { return .limited }
            return .denied
        }
    }
}
