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
        @Bindable var navigator = navigator

        ZStack {
            Group {
                if account.hasSeenWelcome {
                    MainTabView()
                        .transition(.opacity)
                } else {
                    WelcomeView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: account.hasSeenWelcome)
            // Colours resolve through static palette lookups, so a palette change rebuilds
            // the tree to take effect. Tab selection and navigation paths live in Navigator,
            // outside this boundary, so they survive. The rebuild itself is instant; the
            // visible cross-fade is a window snapshot (ThemeStore.crossfade), not two trees.
            .id(theme.palette)
        }
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
        // Presented from here, outside the rebuilt tree, so it stays open while the user
        // tries palettes one after another.
        .sheet(isPresented: $navigator.showAppearance) {
            AppearanceView()
                .environment(theme)
                .preferredColorScheme(theme.mode.colorScheme)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Permissions can change while we are away (Settings, or the limited
                // library picker), so re-read them rather than trusting a stale value.
                permissions.refresh()
                #if DEBUG
                MainThreadWatchdog.shared.resetClock()
                #endif
                scanner.handleForeground(access: permissions.photos)
            case .background:
                scanner.handleBackground()
                if #available(iOS 26.0, *) {
                    Task { await ModelRunner.shared.reset() }
                }
            default:
                break
            }
        }
    }
}
