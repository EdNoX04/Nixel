import SwiftUI

/// Routes a category to its screen. Keeps navigation in one place.
struct CategoryDetailView: View {
    let category: CleanupCategory
    @Environment(ScanCoordinator.self) private var scanner

    var body: some View {
        switch category {
        case .similarPhotos:
            SimilarPhotosView(groups: scanner.similarGroups)
        case .screenshots:
            ScreenshotsView(assets: scanner.screenshots)
        case .blurryPhotos:
            PhotoGridScreen(category: .blurryPhotos,
                            assets: scanner.blurryPhotos,
                            emptyMessage: "No blurry photos found.")
        case .largeVideos:
            LargeVideosView(videos: scanner.largeVideos)
        case .duplicateContacts:
            DuplicateContactsView()
        }
    }
}

/// A flat grid of assets with multi-select — used by Screenshots and Blurry Photos.
struct PhotoGridScreen: View {
    let category: CleanupCategory
    let assets: [PhotoAsset]
    var emptyMessage: String

    @Environment(CleanupSelection.self) private var selection
    @State private var showReview = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    private var allSelected: Bool {
        !assets.isEmpty && assets.allSatisfy { selection.isSelected($0.id, in: category) }
    }

    var body: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView("Nothing here", systemImage: category.icon,
                                       description: Text(emptyMessage))
            } else {
                ScrollView {
                    GridSectionHeader(
                        title: "\(assets.count) \(category.title.lowercased())",
                        subtitle: "Total \(Bytes.string(assets.reduce(0) { $0 + $1.bytes }))",
                        allSelected: allSelected,
                        onToggleAll: toggleAll
                    )
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)

                    if heldBack > 0 { PeopleHeldBackNote(count: heldBack) }

                    LazyVGrid(columns: columns, spacing: 3) {
                        ForEach(assets) { asset in
                            GeometryReader { proxy in
                                AssetThumbnailView(
                                    asset: asset,
                                    side: proxy.size.width,
                                    isSelected: selection.isSelected(asset.id, in: category)
                                ) {
                                    selection.toggle(asset, in: category)
                                }
                            }
                            .aspectRatio(1, contentMode: .fit)
                        }
                    }
                    .padding(.horizontal, 3)
                }
            }
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SwipeReviewView(category: category, assets: assets)
                    } label: {
                        Label("Quick Review", systemImage: "rectangle.stack")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if selection.count(in: category) > 0 {
                SelectionBar(count: selection.count(in: category),
                             bytes: selection.bytes(in: category)) { showReview = true }
            }
        }
        .navigationDestination(isPresented: $showReview) { ReviewView() }
    }

    @State private var heldBack = 0

    private func toggleAll() {
        if allSelected {
            selection.deselect(assets, in: category)
            heldBack = 0
        } else {
            heldBack = selection.selectSkippingPeople(assets, in: category)
        }
    }
}
