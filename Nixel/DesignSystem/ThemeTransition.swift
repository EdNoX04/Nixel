import SwiftUI
import UIKit

// App-only: the widget extension shares AppPalette.swift and cannot reach UIApplication.
extension ThemeStore {
    /// Switches palette with a cross-fade of the whole window.
    func setPalette(_ new: AppPalette) {
        guard new != palette else { return }
        Self.crossfade { self.palette = new }
    }

    /// Switches light/dark/system with the same cross-fade. Without it the colour scheme
    /// snaps, because a trait change is not something SwiftUI animates.
    func setMode(_ new: AppearanceMode) {
        guard new != mode else { return }
        Self.crossfade { self.mode = new }
    }

    /// Cross-dissolves a snapshot of the key window into its next state.
    ///
    /// The previous approach faded the rebuilt SwiftUI tree in over the old one, which for
    /// the length of the fade rendered two complete copies of the app — ambient mesh
    /// background included — and stuttered on device. A window cross-dissolve composites a
    /// snapshot instead, costs next to nothing, and covers what SwiftUI can't animate: the
    /// tab bar, navigation bars, the open sheet and the colour scheme itself.
    @MainActor
    private static func crossfade(_ change: @escaping () -> Void) {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        guard let window, !UIAccessibility.isReduceMotionEnabled else {
            change()
            return
        }
        UIView.transition(with: window, duration: 0.4,
                          options: [.transitionCrossDissolve, .allowUserInteraction,
                                    .curveEaseInOut],
                          animations: change)
    }
}
