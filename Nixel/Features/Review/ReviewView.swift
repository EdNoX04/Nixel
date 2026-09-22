import SwiftUI

/// The last stop before anything is removed.
///
/// Requirement from the brief: "A final screen showing exactly what will be removed and
/// how much space it frees. Nothing is deleted without approval." So this screen states
/// the totals plainly, lets the user drill into and unpick any individual item, and is the
/// only route to the delete action.
struct ReviewView: View {
    @Environment(CleanupSelection.self) private var selection
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(\.dismiss) private var dismiss

    @State private var runner = CleanupRunner()
    @State private var confirming = false
    @State private var summary: CleanupSummary?

    private var categories: [CleanupCategory] {
        CleanupCategory.allCases.filter { selection.count(in: $0) > 0 }
    }

    var body: some View {
        Group {
            if selection.isEmpty {
                ContentUnavailableView("Nothing selected", systemImage: "checkmark.circle",
                                       description: Text("Choose items to remove and they'll appear here."))
            } else {
                content
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { deleteBar }
        .confirmationDialog(
            "Delete \(selection.totalCount) item\(selection.totalCount == 1 ? "" : "s")?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Delete \(selection.totalCount) Item\(selection.totalCount == 1 ? "" : "s")",
                   role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("iOS will ask you to confirm as well. Items move to Recently Deleted, where they can still be recovered for 30 days.")
        }
        .navigationDestination(item: $summary) { CleanupSummaryView(summary: $0) }
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                totalCard

                ForEach(categories) { category in
                    categorySection(category)
                }

                iCloudNotice
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.lg)
        }
    }

    private var totalCard: some View {
        VStack(spacing: Theme.Space.xs) {
            Text(Bytes.string(selection.totalBytes))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.success)
            Text("will be freed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(selection.totalCount) item\(selection.totalCount == 1 ? "" : "s") selected")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func categorySection(_ category: CleanupCategory) -> some View {
        let items = selection.selectedItems(in: category)
        return VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Label(category.title, systemImage: category.icon)
                    .font(.headline)
                    .foregroundStyle(category.tint)
                Spacer()
                Text("\(items.count) · \(Bytes.string(selection.bytes(in: category)))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Space.sm) {
                    ForEach(items) { asset in
                        AssetThumbnailView(asset: asset, side: 74, isSelected: true) {
                            // Tapping here unpicks the item — the review screen has to be
                            // a place you can change your mind, not just a confirmation.
                            selection.toggle(asset, in: category)
                        }
                    }
                }
            }
        }
    }

    private var iCloudNotice: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
            Text("If iCloud Photos is on, these are removed from your other devices too.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: Delete

    @ViewBuilder
    private var deleteBar: some View {
        if !selection.isEmpty {
            VStack(spacing: Theme.Space.sm) {
                if case .failed(let message) = runner.outcome {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .multilineTextAlignment(.center)
                }
                if runner.outcome == .cancelled {
                    Text("Nothing was deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    confirming = true
                } label: {
                    if runner.isRunning {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Delete \(selection.totalCount) Item\(selection.totalCount == 1 ? "" : "s") · \(Bytes.string(selection.totalBytes))")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(GlassActionButtonStyle(tint: Theme.danger))
                .disabled(runner.isRunning)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, Theme.Space.lg)
            .glassBar(cornerRadius: 30)
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.sm)
        }
    }

    private func performDelete() async {
        let assets = selection.allSelectedAssets
        let freed = assets.reduce(Int64(0)) { $0 + $1.bytes }
        let removed = await runner.delete(assets)

        guard !removed.isEmpty else { return }

        selection.remove(ids: removed)
        scanner.removeDeleted(ids: removed)
        scanner.refreshStorage()
        summary = CleanupSummary(count: removed.count, bytes: freed)
    }
}

/// What a completed cleanup freed.
struct CleanupSummary: Identifiable, Hashable {
    var id: String { "\(count)-\(bytes)" }
    let count: Int
    let bytes: Int64
}
