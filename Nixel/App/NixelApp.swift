import SwiftUI

@main
struct NixelApp: App {
    @State private var permissions = PermissionCenter()

    init() {
        // Background task handlers must be registered before launch finishes,
        // otherwise BGTaskScheduler traps.
        NixelAgent.shared.register()
        #if DEBUG
        Trace.reset()
        trace("app launched")
        MainThreadWatchdog.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(permissions)
        }
    }
}
