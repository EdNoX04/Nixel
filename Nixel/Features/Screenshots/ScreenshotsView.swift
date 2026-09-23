import SwiftUI

/// Screenshots, sorted by what they actually are.
///
/// A flat grid of 400 screenshots is a list, not a decision. On-device intelligence reads
/// the text in each one and sorts them into what is safe to clear (memes, app UI) and what
/// is worth a second look (receipts, tickets, verification codes). The user still approves
/// everything — this only changes the order in which they see it, and which ones get
/// pre-selected by "select all".
struct ScreenshotsView: View {
    let assets: [PhotoAsset]

    @Environment(ScanCoordinator.self) private var scanner
    @Environment(CleanupSelection.self) private var selection
    @Environment(Navigator.self) private var navigator
    @State private var heldBack = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    // MARK: Buckets

    private var verdicts: [String: ScreenshotVerdict] { scanner.screenshotVerdicts }

    private var safe: [PhotoAsset] {
        assets.filter { verdicts[$0.id]?.safeToDelete == true }
    }

    private var worthKeeping: [PhotoAsset] {
        assets.filter { verdicts[$0.id].map { !$0.safeToDelete && $0.kind.isSensitive } == true }
    }

    private var unsorted: [PhotoAsset] {
        let handled = Set(safe.map(\.id)).union(worthKeeping.map(\.id))
        return assets.filter { !handled.contains($0.id) }
    }

    private var triageReady: Bool {
        IntelligenceService.shared.availability.isAvailable && !verdicts.isEmpty
    }

    var body: some View {
        Group {
            if assets.isEmpty {
                ContentUnavailableView("No screenshots", systemImage: "iphone.gen3",
                                       description: Text("Nothing captured on this iPhone."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        if scanner.isTriaging {
                            triageProgress
                        }

                        if heldBack > 0 {
                            PeopleHeldBackNote(count: heldBack)
                                .padding(.horizontal, Theme.Space.lg)
                        }

                        if triageReady {
                            if !safe.isEmpty {
                                section("Safe to clear",
                                        subtitle: "Memes, app screens and throwaways",
                                        tint: Theme.success,
                                        icon: "checkmark.circle.fill",
                                        items: safe)
                            }
                            if !worthKeeping.isEmpty {
                                section("Worth a look first",
                                        subtitle: "These look like receipts, passes or codes",
                                        tint: Theme.warning,
                                        icon: "exclamationmark.triangle.fill",
                                        items: worthKeeping,
                                        showsVerdict: true)
                            }
                            if !unsorted.isEmpty {
                                section("Everything else", subtitle: nil,
                                        tint: .secondary, icon: "square.grid.2x2",
                                        items: unsorted)
                            }
                        } else {
                            section("\(assets.count) screenshots",
                                    subtitle: "Total \(Bytes.string(assets.reduce(0) { $0 + $1.bytes }))",
                                    tint: Theme.screenshots,
                                    icon: "iphone.gen3",
                                    items: assets)
                        }
                    }
                    .padding(.vertical, Theme.Space.md)
                }
            }
        }
        .navigationTitle("Screenshots")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !assets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.quickReview(.screenshots)) {
                        Label("Quick Review", systemImage: "rectangle.stack")
                    }
                }
            }
        }
        .selectionBar(count: selection.count(in: .screenshots),
                      bytes: selection.bytes(in: .screenshots)) { navigator.push(.review) }
    }

    // MARK: Pieces

    private var triageProgress: some View {
        HStack(spacing: Theme.Space.md) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sorting your screenshots")
                    .font(.subheadline.weight(.medium))
                Text("Reading them on this iPhone — nothing is uploaded")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.indigo.opacity(0.10))
        )
        .padding(.horizontal, Theme.Space.lg)
    }

    @ViewBuilder
    private func section(
        _ title: String,
        subtitle: String?,
        tint: Color,
        icon: String,
        items: [PhotoAsset],
        showsVerdict: Bool = false
    ) -> some View {
        let allSelected = !items.isEmpty && items.allSatisfy { selection.isSelected($0.id, in: .screenshots) }

        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                        .foregroundStyle(tint)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(items.count) · \(Bytes.string(items.reduce(0) { $0 + $1.bytes }))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    withAnimation(.snappy(duration: 0.25)) {
                        if allSelected {
                            selection.deselect(items, in: .screenshots)
                            heldBack = 0
                        } else {
                            heldBack = selection.selectSkippingPeople(items, in: .screenshots)
                        }
                    }
                }
                .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, Theme.Space.lg)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(items) { asset in
                    VStack(spacing: 3) {
                        GeometryReader { proxy in
                            AssetThumbnailView(
                                asset: asset,
                                side: proxy.size.width,
                                isSelected: selection.isSelected(asset.id, in: .screenshots)
                            ) {
                                selection.toggle(asset, in: .screenshots)
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)

                        if showsVerdict, let verdict = verdicts[asset.id] {
                            Text(verdict.kind.label)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.warning)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 3)
        }
    }
}
