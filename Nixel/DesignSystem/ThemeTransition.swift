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

// MARK: App icon

extension AppPalette {
    /// The alternate icon drawn in this palette's colours. Forest is the primary icon.
    var iconName: String? {
        switch self {
        case .forest:     return nil
        case .mocha:      return "AppIcon-Mocha"
        case .buttermilk: return "AppIcon-Buttermilk"
        case .blush:      return "AppIcon-Blush"
        case .twinkle:    return "AppIcon-Twinkle"
        }
    }

    /// The icon's ground and mark, light then dark — the same values the icon PNGs were
    /// recoloured with, so the in-app preview matches the Home Screen.
    var iconColours: (light: (ground: Color, mark: Color), dark: (ground: Color, mark: Color)) {
        switch self {
        case .forest:     return ((Color(hex: 0xF0ECE4), Color(hex: 0x174036)), (Color(hex: 0x0C2B24), Color(hex: 0xE1EAE1)))
        case .mocha:      return ((Color(hex: 0xEDE3D6), Color(hex: 0x553528)), (Color(hex: 0x291C0E), Color(hex: 0xE6D8C6)))
        case .buttermilk: return ((Color(hex: 0xFFF2BA), Color(hex: 0x0F3C65)), (Color(hex: 0x0B2D4D), Color(hex: 0xFFF2BA)))
        case .blush:      return ((Color(hex: 0xEEE4DA), Color(hex: 0x4D0E13)), (Color(hex: 0x3A0B10), Color(hex: 0xEBD3CC)))
        case .twinkle:    return ((Color(hex: 0xEFE4D6), Color(hex: 0x2B3442)), (Color(hex: 0x1B2230), Color(hex: 0xD9A87C)))
        }
    }
}

extension ThemeStore {
    /// Brings the Home Screen icon in line with the palette (or back to the primary icon
    /// when matching is off). Called when the Appearance sheet closes rather than on every
    /// tap: iOS confirms each icon change with an alert, and trying palettes one after
    /// another shouldn't raise one each time.
    @MainActor
    func applyIcon() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons else { return }
        let wanted = matchesIcon ? palette.iconName : nil
        guard app.alternateIconName != wanted else { return }
        app.setAlternateIconName(wanted) { _ in }
    }
}
