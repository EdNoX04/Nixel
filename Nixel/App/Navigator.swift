import SwiftUI

/// Owns which tab is showing and each tab's navigation path.
///
/// Paths are per-tab rather than shared: switching tabs mid-review should leave the other
/// tabs exactly as they were. The cleanup summary also needs to pop its own tab back to
/// root — going "back" from it would land on a review screen listing items that no longer
/// exist — and that requires control of that specific path.
@Observable
@MainActor
final class Navigator {
    var selectedTab: TabItem = .storage
    private var paths: [TabItem: NavigationPath] = [:]

    func binding(for tab: TabItem) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Clears the current tab's stack.
    func popToRoot() {
        paths[selectedTab] = NavigationPath()
    }

    func show(_ tab: TabItem) {
        selectedTab = tab
    }
}
