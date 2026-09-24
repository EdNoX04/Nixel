import SwiftUI

/// Similar photos, grouped.
///
/// The safety rule that shapes this screen: the photo we think is best is never selected
/// by a bulk action. "Select all" inside a group means "everything except the keeper", so
/// a user tapping quickly through can never wipe out an entire group by accident.
struct SimilarPhotosView: View {
    let groups: [PhotoGroup]

    @Environment(CleanupSelection.self) private var selection
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(Navigator.self) private var navigator
    @State private var heldBack = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        Group {
            // Blurry lives on this tab, so its card shows even when there are no groups.
            if groups.isEmpty && !scanner.summary(.blurryPhotos).hasFindings {
                ScanPendingView(category: .similarPhotos,
                                emptyTitle: "No similar photos",
                                emptyMessage: "Nothing in your library looks like a repeat.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                        IntelligenceUnavailableNote(
                            effect: "Groups are shown by size rather than named by what's in them")
                        if heldBack > 0 { PeopleHeldBackNote(count: heldBack) }

                        if scanner.summary(.blurryPhotos).hasFindings {
                            NavigationLink(value: Route.category(.blurryPhotos)) {
                                CategoryCard(category: .blurryPhotos,
                                             summary: scanner.summary(.blurryPhotos))
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(groups) { group in
                            groupSection(group)
                                // Keyed on availability: a row that appeared before Apple
                                // Intelligence finished starting up asks again once it has,
                                // instead of staying unnamed.
                                .task(id: IntelligenceService.shared.availability.isAvailable) {
                                    scanner.describeGroup(group)
                                }
                        }
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
        .navigationTitle("Similar Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !groups.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Select All Extras", action: selectAllExtras)
                        .font(.subheadline)
                }
            }
        }
        .selectionBar(count: selection.count(in: .similarPhotos),
                      bytes: selection.bytes(in: .similarPhotos)) { navigator.push(.review) }
    }

    @ViewBuilder
    private func groupSection(_ group: PhotoGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            GridSectionHeader(
                title: scanner.groupLabels[group.id] ?? "\(group.assets.count) similar",
                subtitle: "\(group.assets.count) shots · keep 1 · free \(Bytes.string(group.reclaimableBytes))",
                allSelected: selection.isBulkSelected(group.others, in: .similarPhotos),
                onToggleAll: { toggleGroup(group) },
                pickByHand: CleanupSelection.bulkSelectable(group.others).isEmpty
            )

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(group.assets) { asset in
                    GeometryReader { proxy in
                        AssetThumbnailView(
                            asset: asset,
                            side: proxy.size.width,
                            isSelected: selection.isSelected(asset.id, in: .similarPhotos),
                            showsBestBadge: asset.id == group.bestID
                        ) {
                            selection.toggle(asset, in: .similarPhotos)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }

    private func toggleGroup(_ group: PhotoGroup) {
        let extras = group.others
        if selection.isBulkSelected(extras, in: .similarPhotos) {
            selection.deselect(extras, in: .similarPhotos)
            heldBack = 0
        } else {
            heldBack = selection.selectSkippingPeople(extras, in: .similarPhotos)
        }
    }

    private func selectAllExtras() {
        withAnimation(.snappy(duration: 0.25)) {
            heldBack = selection.selectSkippingPeople(groups.flatMap(\.others), in: .similarPhotos)
        }
    }
}
