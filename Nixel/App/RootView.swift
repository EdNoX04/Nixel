import SwiftUI
import Photos

struct RootView: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(\.scenePhase) private var scenePhase
    @State private var scanner = ScanCoordinator()
    @State private var selection = CleanupSelection()
    @State private var navigator = Navigator()
    @State private var account = AccountStore()
    @State private var theme = ThemeStore()

    var body: some View {
        Group {
            if account.hasSeenWelcome {
                NavigationStack(path: $navigator.path) {
                    DashboardView()
                }
                .transition(.opacity)
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: account.hasSeenWelcome)
        // Colours resolve through static palette lookups, so a palette change has to
        // rebuild the tree to take effect. The picker is a sheet over the dashboard —
        // already the root — so nothing navigational is lost.
        .id(theme.palette)
        .preferredColorScheme(theme.mode.colorScheme)
        // These must sit on the stack, not on DashboardView: destinations pushed via
        // `navigationDestination` do not inherit environment applied inside the stack,
        // and a missing @Environment object is a hard crash, not a soft failure.
        .environment(scanner)
        .environment(selection)
        .environment(navigator)
        .environment(account)
        .environment(theme)
        .tint(Theme.indigo)
        .onChange(of: scenePhase) { _, phase in
            // Permissions can change while we are backgrounded (Settings, or the limited
            // library picker), so re-read them rather than trusting a stale value.
            if phase == .active {
                permissions.refresh()
                scanner.refreshStorage()
            }
        }
    }
}
