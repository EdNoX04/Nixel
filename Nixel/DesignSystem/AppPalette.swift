import SwiftUI

/// A complete set of colour tokens, in light and dark renditions.
///
/// Every colour the app draws comes from one of these. A palette must supply both
/// renditions for each token: a value tuned against white is almost always too dark and
/// too saturated against near-black, which is how apps end up with unreadable accents in
/// dark mode.
struct PaletteSpec {
    typealias Pair = (light: UInt32, dark: UInt32)

    var primary: Pair            // brand, buttons, the storage ring
    var secondary: Pair          // the far end of the brand gradient

    var similar: Pair
    var screenshots: Pair
    var videos: Pair
    var contacts: Pair
    var blurry: Pair

    var danger: Pair
    var success: Pair
    var warning: Pair

    /// The welcome screen's full-bleed gradient, which sits on its own dark surface.
    var welcome: [UInt32]
}

/// The palettes the user can choose between.
enum AppPalette: String, CaseIterable, Identifiable, Codable {
    case forest
    case mocha
    case buttermilk
    case blush
    case twinkle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest:     return "Forest"
        case .mocha:      return "Mocha"
        case .buttermilk: return "Buttermilk"
        case .blush:      return "Blush"
        case .twinkle:    return "Twinkle"
        }
    }

    var subtitle: String {
        switch self {
        case .forest:     return "Deep greens"
        case .mocha:      return "Espresso and taupe"
        case .buttermilk: return "Cream and midnight blue"
        case .blush:      return "Sand, rose and burgundy"
        case .twinkle:    return "Night navy and tan"
        }
    }

    /// Swatches shown in the picker.
    var swatches: [Color] {
        let spec = self.spec
        return [spec.primary, spec.secondary, spec.screenshots, spec.similar]
            .map { Color(hex: $0.light) }
    }

    var spec: PaletteSpec {
        switch self {

        // #051F20 #0B2B26 #163832 #235347 #8EB69B #DAF1DE
        case .forest:
            return PaletteSpec(
                primary:     (0x235347, 0x8EB69B),
                secondary:   (0x163832, 0xDAF1DE),
                similar:     (0x235347, 0x8EB69B),
                screenshots: (0xB07A2E, 0xE3B063),
                videos:      (0x9E4A3C, 0xE08C7A),
                contacts:    (0x2E6F7A, 0x7FC3CE),
                blurry:      (0x5C6B64, 0xA7B5AE),
                danger:      (0xB3453C, 0xF08A80),
                success:     (0x2E7D5B, 0x7FD1A8),
                warning:     (0xA87527, 0xE8B45E),
                welcome:     [0x051F20, 0x163832, 0x235347]
            )

        // #291C0E #6E473B #A78D78 #BEB5A9 #E1D4C2
        case .mocha:
            return PaletteSpec(
                primary:     (0x6E473B, 0xC0A48F),
                secondary:   (0x291C0E, 0xE1D4C2),
                similar:     (0x6E473B, 0xC0A48F),
                screenshots: (0xA9732B, 0xE0B274),
                videos:      (0x8C4A3C, 0xDB9280),
                contacts:    (0x5E6B6B, 0xA9BCBC),
                blurry:      (0x8A8175, 0xBEB5A9),
                danger:      (0xA34338, 0xE8897C),
                success:     (0x4F7A52, 0x9BC79C),
                warning:     (0xA9732B, 0xE0B274),
                welcome:     [0x291C0E, 0x6E473B, 0xA78D78]
            )

        // #FFF2BA buttermilk · #0F3C65 midnight blue
        case .buttermilk:
            return PaletteSpec(
                primary:     (0x0F3C65, 0xFFF2BA),
                secondary:   (0x2E5C8A, 0x1E5A8F),
                similar:     (0x0F3C65, 0xE8DCA4),
                screenshots: (0xC9952A, 0xF0CE72),
                videos:      (0x9B3F52, 0xE8919F),
                contacts:    (0x2C6E8F, 0x86BEDA),
                blurry:      (0x6B7280, 0xAEB6C2),
                danger:      (0xA5303A, 0xEC7F88),
                success:     (0x2B7355, 0x7FCBA3),
                warning:     (0xC9952A, 0xF0CE72),
                welcome:     [0x0F3C65, 0x1E5A8F, 0xC9B36A]
            )

        // #EEE4DA creme · #D8C4AC sand · #C8A49F dusty pink · #4D0E13 burgundy
        case .blush:
            return PaletteSpec(
                primary:     (0x4D0E13, 0xD8A9A4),
                secondary:   (0xC8A49F, 0xEEE4DA),
                similar:     (0x7A2A30, 0xD8A9A4),
                screenshots: (0xA98243, 0xD8C4AC),
                videos:      (0x8C3742, 0xDC8C96),
                contacts:    (0x5F6F72, 0xA9BCC0),
                blurry:      (0x8A7F79, 0xC3B7B0),
                danger:      (0x9B2630, 0xE8858F),
                success:     (0x4A7A5C, 0x93C9A8),
                warning:     (0xA98243, 0xE0C089),
                welcome:     [0x4D0E13, 0x8C3742, 0xC8A49F]
            )

        // Night navy with a warm tan accent.
        case .twinkle:
            return PaletteSpec(
                primary:     (0x3A4A63, 0xD9A87C),
                secondary:   (0x2B3442, 0xA8B5B8),
                similar:     (0x3A4A63, 0xA8B5B8),
                screenshots: (0xB07A42, 0xD9A87C),
                videos:      (0x8C5A5A, 0xD89A9A),
                contacts:    (0x4A6B7A, 0x93B8C4),
                blurry:      (0x6B7280, 0xA8B5B8),
                danger:      (0xA23F45, 0xE8888E),
                success:     (0x3F7A63, 0x8CC9B0),
                warning:     (0xB07A42, 0xE0B583),
                welcome:     [0x1F2632, 0x2B3442, 0x3A4A63]
            )
        }
    }

    // MARK: Current selection

    /// Mirrored as a plain static so `Theme` can read it from anywhere without hopping
    /// actors. `ThemeStore` is the only writer.
    nonisolated(unsafe) static var current: AppPalette = .forest
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Light, dark, or whatever the phone is doing.
enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "iphone"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    /// `nil` hands the decision back to iOS.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Owns the chosen palette and persists it.
@Observable
@MainActor
final class ThemeStore {

    private let key = "appearance.palette"
    private let modeKey = "appearance.mode"

    var palette: AppPalette {
        didSet {
            AppPalette.current = palette
            UserDefaults.standard.set(palette.rawValue, forKey: key)
        }
    }

    var mode: AppearanceMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: modeKey) }
    }

    init() {
        let saved = UserDefaults.standard.string(forKey: key)
        let resolved = saved.flatMap(AppPalette.init(rawValue:)) ?? .forest
        palette = resolved
        AppPalette.current = resolved
        mode = UserDefaults.standard.string(forKey: modeKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }
}
