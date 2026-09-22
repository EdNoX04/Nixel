import SwiftUI

/// Owns the navigation stack's path so any screen can return to the dashboard.
///
/// Needed because the cleanup summary deliberately hides its back button — going "back"
/// from it would land on a review screen listing items that no longer exist. It needs to
/// pop all the way to the root instead, which requires control of the path.
@Observable
@MainActor
final class Navigator {
    var path = NavigationPath()

    func popToRoot() {
        path = NavigationPath()
    }
}
