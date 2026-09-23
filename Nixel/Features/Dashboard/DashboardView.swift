import SwiftUI
import Photos

extension UIApplication {
    /// Finds the frontmost view controller — needed because `presentLimitedLibraryPicker`
    /// is UIKit-only and has no SwiftUI equivalent.
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
