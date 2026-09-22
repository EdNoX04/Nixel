import SwiftUI
import UIKit

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
    case sageGold
    case slate
    case nixel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forest:   return "Forest"
        case .sageGold: return "Sage & Gold"
        case .slate:    return "Slate"
        case .nixel:    return "Original"
        }
    }

    var subtitle: String {
        switch self {
        case .forest:   return "Deep greens"
        case .sageGold: return "Sage and warm gold"
        case .slate:    return "Navy and cool blues"
        case .nixel:    return "Violet and teal"
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

        // #6D9773 #0C3B2E #BB8A52 #FFBA00
        case .sageGold:
            return PaletteSpec(
                primary:     (0x0C3B2E, 0x6D9773),
                secondary:   (0x6D9773, 0xA8C4AE),
                similar:     (0x2E7D6B, 0x6D9773),
                screenshots: (0xC9930F, 0xFFBA00),
                videos:      (0xA3703C, 0xBB8A52),
                contacts:    (0x246B7A, 0x7FBDCB),
                blurry:      (0x76837C, 0xADB8B2),
                danger:      (0xB0463A, 0xEE8A7C),
                success:     (0x2F7A4F, 0x82CFA0),
                warning:     (0xC9930F, 0xFFBA00),
                welcome:     [0x0C3B2E, 0x235844, 0x6D9773]
            )

        // #00002A #1A3F75 and the cooler steps above them
        case .slate:
            return PaletteSpec(
                primary:     (0x1A3F75, 0x9BB8D3),
                secondary:   (0x00002A, 0x5C7FA8),
                similar:     (0x1A3F75, 0x9BB8D3),
                screenshots: (0xA8761F, 0xE2B25C),
                videos:      (0x9B3F52, 0xE08196),
                contacts:    (0x2C6E8F, 0x86BEDA),
                blurry:      (0x5E6B7A, 0xA6B3C0),
                danger:      (0xA93B44, 0xEE858E),
                success:     (0x2B7355, 0x7FCBA3),
                warning:     (0xA8761F, 0xE2B25C),
                welcome:     [0x00002A, 0x1A3F75, 0x3E6491]
            )

        case .nixel:
            return PaletteSpec(
                primary:     (0x5D4FEF, 0x9289FC),
                secondary:   (0x0D9488, 0x34C6B7),
                similar:     (0x6B5CF2, 0x9C93FD),
                screenshots: (0xDA7D17, 0xFCAD49),
                videos:      (0xDA415D, 0xFC768D),
                contacts:    (0x1C8BCC, 0x66BDF9),
                blurry:      (0x746982, 0xAFA5BB),
                danger:      (0xD43740, 0xFC7373),
                success:     (0x169960, 0x4AD392),
                warning:     (0xB87A0E, 0xF9BF45),
                welcome:     [0x3D319E, 0x294D94, 0x086160]
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
