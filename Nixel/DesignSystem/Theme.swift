import SwiftUI
import UIKit

/// Central design tokens. Everything visual in Nixel pulls from here so the app reads as
/// one system in both light and dark mode.
///
/// Brand and category colours are *adaptive*, not fixed. A single sRGB value that looks
/// right on white will usually be too dark and too saturated against a near-black
/// background, so each token declares both renditions and iOS resolves it per trait.
enum Theme {

    // MARK: Helper

    private static func adaptive(
        light: (r: Double, g: Double, b: Double),
        dark: (r: Double, g: Double, b: Double)
    ) -> Color {
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }

    // MARK: Brand

    static let indigo = adaptive(light: (0.365, 0.310, 0.937), dark: (0.573, 0.537, 0.988))
    static let teal   = adaptive(light: (0.051, 0.580, 0.533), dark: (0.204, 0.776, 0.718))

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [indigo, teal], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Category accents
    //
    // Each cleanup category owns one hue so a colour alone identifies it on the dashboard,
    // in the review list and on the summary screen.

    static let similar     = adaptive(light: (0.420, 0.360, 0.950), dark: (0.612, 0.576, 0.992))
    static let screenshots = adaptive(light: (0.855, 0.490, 0.090), dark: (0.988, 0.678, 0.286))
    static let videos      = adaptive(light: (0.855, 0.255, 0.365), dark: (0.988, 0.463, 0.553))
    static let contacts    = adaptive(light: (0.110, 0.545, 0.800), dark: (0.400, 0.741, 0.976))
    static let blurry      = adaptive(light: (0.455, 0.412, 0.510), dark: (0.686, 0.647, 0.733))

    // MARK: Semantic

    static let danger  = adaptive(light: (0.831, 0.216, 0.239), dark: (0.988, 0.451, 0.451))
    static let success = adaptive(light: (0.086, 0.600, 0.373), dark: (0.290, 0.827, 0.573))
    static let warning = adaptive(light: (0.722, 0.475, 0.055), dark: (0.976, 0.749, 0.271))

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
