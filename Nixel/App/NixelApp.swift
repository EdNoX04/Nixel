import SwiftUI

@main
struct NixelApp: App {
    @State private var permissions = PermissionCenter()

    init() {
        // Background task handlers must be registered before launch finishes,
        // otherwise BGTaskScheduler traps.
        NixelAgent.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(permissions)
        }
    }
}
