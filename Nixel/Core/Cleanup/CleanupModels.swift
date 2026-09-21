import SwiftUI

/// The cleanup surfaces Nixel offers. Order here is the order shown on the dashboard.
enum CleanupCategory: String, CaseIterable, Identifiable, Hashable {
    case similarPhotos
    case screenshots
    case largeVideos
    case blurryPhotos
    case duplicateContacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .similarPhotos:     return "Similar Photos"
        case .screenshots:       return "Screenshots"
        case .largeVideos:       return "Large Videos"
        case .blurryPhotos:      return "Blurry Photos"
        case .duplicateContacts: return "Duplicate Contacts"
        }
    }

    var subtitle: String {
        switch self {
        case .similarPhotos:     return "Near-identical shots and duplicates"
        case .screenshots:       return "Everything you've captured"
        case .largeVideos:       return "Biggest videos first"
        case .blurryPhotos:      return "Out-of-focus shots"
        case .duplicateContacts: return "Merge or remove repeats"
        }
    }

    var icon: String {
        switch self {
        case .similarPhotos:     return "square.on.square"
        case .screenshots:       return "iphone.gen3"
        case .largeVideos:       return "film.stack"
        case .blurryPhotos:      return "camera.filters"
        case .duplicateContacts: return "person.2"
        }
    }

    var tint: Color {
        switch self {
        case .similarPhotos:     return Theme.similar
        case .screenshots:       return Theme.screenshots
        case .largeVideos:       return Theme.videos
        case .blurryPhotos:      return Theme.blurry
        case .duplicateContacts: return Theme.contacts
        }
    }

    /// Contacts don't meaningfully free disk space — we count them, not bytes.
    var measuresBytes: Bool { self != .duplicateContacts }
}

/// Where a category is in its scan lifecycle.
enum CategoryState: Equatable {
    case idle
    case scanning(Double)      // 0...1
    case ready
    case blocked(String)       // permission or capability problem, with a reason to show

    var isScanning: Bool { if case .scanning = self { return true }; return false }
}

/// What the dashboard shows for one category.
struct CategorySummary: Equatable {
    var state: CategoryState = .idle
    var itemCount: Int = 0
    var reclaimableBytes: Int64 = 0

    var hasFindings: Bool { itemCount > 0 }
}
