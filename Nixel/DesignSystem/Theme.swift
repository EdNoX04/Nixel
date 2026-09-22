import SwiftUI
import UIKit

/// Central design tokens.
///
/// Every colour resolves through the currently selected `AppPalette` and is *adaptive*:
/// each token declares a light and a dark rendition and iOS picks per trait. That matters
/// more than it sounds — a single sRGB value tuned against white is reliably too dark and
/// too saturated against a near-black background, which is how accents end up unreadable
/// in dark mode.
enum Theme {

    // MARK: Resolution

    private static func adaptive(_ pair: PaletteSpec.Pair) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    private static var spec: PaletteSpec { AppPalette.current.spec }

    // MARK: Brand

    /// Kept named `indigo`/`teal` because they are used as brand roles throughout, not
    /// as literal hues — the palette decides what colour they actually are.
    static var indigo: Color { adaptive(spec.primary) }
    static var teal: Color { adaptive(spec.secondary) }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [indigo, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The welcome screen's full-bleed background.
    static var welcomeGradient: LinearGradient {
        LinearGradient(colors: spec.welcome.map { Color(hex: $0) },
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Category accents
    //
    // Each cleanup category owns one hue so a colour alone identifies it on the dashboard,
    // in the review list and on the summary screen.

    static var similar: Color { adaptive(spec.similar) }
    static var screenshots: Color { adaptive(spec.screenshots) }
    static var videos: Color { adaptive(spec.videos) }
    static var contacts: Color { adaptive(spec.contacts) }
    static var blurry: Color { adaptive(spec.blurry) }

    // MARK: Semantic

    static var danger: Color { adaptive(spec.danger) }
    static var success: Color { adaptive(spec.success) }
    static var warning: Color { adaptive(spec.warning) }

    // MARK: Layout

    enum Radius {
        static let card: CGFloat = 16
        static let tile: CGFloat = 12
        static let thumb: CGFloat = 8
        static let pill: CGFloat = 999
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

// MARK: - Byte formatting
//
// One formatter for the whole app: a "space freed" number that disagrees with itself
// between screens instantly reads as a bug, and this app is entirely about that number.

enum Bytes {
    private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file          // matches what iOS Settings shows
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 MB" }
        return formatter.string(fromByteCount: bytes)
    }

    static func string(_ bytes: Int) -> String { string(Int64(bytes)) }
}
