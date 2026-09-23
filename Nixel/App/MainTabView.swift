import SwiftUI

/// The app's five destinations.
enum TabItem: String, Hashable, CaseIterable, Identifiable {
    case storage, similar, screenshots, videos, contacts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .storage:     return "Storage"
        case .similar:     return "Similar"
        case .screenshots: return "Screens"
        case .videos:      return "Videos"
        case .contacts:    return "Contacts"
        }
    }

    var icon: String {
        switch self {
        case .storage:     return "internaldrive.fill"
        case .similar:     return "square.on.square"
        case .screenshots: return "iphone.gen3"
        case .videos:      return "film.stack"
        case .contacts:    return "person.2.fill"
        }
    }

    /// The cleanup category this tab shows, if any.
    var category: CleanupCategory? {
        switch self {
        case .storage:     return nil
        case .similar:     return .similarPhotos
        case .screenshots: return .screenshots
        case .videos:      return .largeVideos
        case .contacts:    return .duplicateContacts
        }
    }
}

/// Root navigation.
///
/// On iOS 26 and later this is the system tab bar, which renders as a floating Liquid
/// Glass pill over the content and minimises out of the way as you scroll. Below that it
/// falls back to the classic bar — same destinations, same structure, just an opaque bar.
///
/// Each tab owns its own navigation path, so drilling into a review on one tab and
/// switching away does not disturb the others, and the cleanup summary can pop its own
/// tab back to root without touching the rest.
struct MainTabView: View {
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator

        if #available(iOS 26.0, *) {
            TabView(selection: $navigator.selectedTab) {
                ForEach(TabItem.allCases) { item in
                    Tab(item.title, systemImage: item.icon, value: item) {
                        stack(for: item)
                    }
                }
            }
            // Not `.onScrollDown`: the storage tab does not scroll, so a bar minimised on
            // another tab stayed collapsed here and read as a stray floating button.
        } else {
            TabView(selection: $navigator.selectedTab) {
                ForEach(TabItem.allCases) { item in
                    stack(for: item)
                        .tabItem { Label(item.title, systemImage: item.icon) }
                        .tag(item)
                }
            }
        }
    }

    @ViewBuilder
    private func stack(for item: TabItem) -> some View {
        @Bindable var navigator = navigator

        NavigationStack(path: navigator.binding(for: item)) {
            Group {
                switch item {
                case .storage:
                    StorageTabView()
                case .similar:
                    SimilarPhotosView(groups: scanner.similarGroups)
                case .screenshots:
                    ScreenshotsView(assets: scanner.screenshots)
                case .videos:
                    LargeVideosView(videos: scanner.largeVideos)
                case .contacts:
                    DuplicateContactsView()
                }
            }
            // Registered once, at the root of each stack. Declaring destinations on the
            // screens themselves registered the same type twice whenever one of those
            // screens was pushed onto another.
            .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// Builds the screen for a route.
struct RouteView: View {
    let route: Route
    @Environment(ScanCoordinator.self) private var scanner

    var body: some View {
        switch route {
        case .category(let category):
            CategoryDetailView(category: category)
        case .review:
            ReviewView()
        case .summary(let summary):
            CleanupSummaryView(summary: summary)
        case .quickReview(let category):
            SwipeReviewView(category: category, assets: assets(in: category))
        }
    }

    private func assets(in category: CleanupCategory) -> [PhotoAsset] {
        switch category {
        case .screenshots:   return scanner.screenshots
        case .largeVideos:   return scanner.largeVideos
        case .blurryPhotos:  return scanner.blurryPhotos
        case .similarPhotos: return scanner.similarGroups.flatMap(\.others)
        case .duplicateContacts: return []
        }
    }
}
