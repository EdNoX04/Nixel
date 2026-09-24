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
        // `-NixelColdScan YES` on launch: forget every analysed photo, to time a
        // first-time scan. Debug builds only; the demo library is re-analysed from scratch.
        if UserDefaults.standard.bool(forKey: "NixelColdScan") {
            let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask)[0]
            try? FileManager.default.removeItem(at: support.appendingPathComponent("featureprints.bin"))
            trace("cold scan requested: analysis cache cleared")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(permissions)
        }
    }
}
