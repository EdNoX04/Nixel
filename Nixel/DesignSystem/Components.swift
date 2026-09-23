import SwiftUI

/// One tappable category row on the dashboard.
struct CategoryCard: View {
    var category: CleanupCategory
    var summary: CategorySummary

    var body: some View {
        HStack(spacing: Theme.Space.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(category.tint.opacity(0.15))
                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(category.tint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.headline)
                detail
            }

            Spacer(minLength: 4)

            trailing
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    @ViewBuilder
    private var detail: some View {
        switch summary.state {
        case .idle:
            Text(category.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .scanning:
            Text("Scanning…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .blocked(let reason):
            Text(reason)
                .font(.subheadline)
                .foregroundStyle(Theme.warning)
        case .ready:
            if summary.hasFindings {
                Text(readyDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Nothing to clean")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var readyDetail: String {
        let noun = category == .duplicateContacts ? "duplicate" : "item"
        let count = "\(summary.itemCount) \(noun)\(summary.itemCount == 1 ? "" : "s")"
        guard category.measuresBytes, summary.reclaimableBytes > 0 else { return count }
        return "\(count) · \(Bytes.string(summary.reclaimableBytes))"
    }

    @ViewBuilder
    private var trailing: some View {
        switch summary.state {
        case .scanning(let p):
            ProgressView(value: max(0.02, p))
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .ready where summary.hasFindings:
            HStack(spacing: 4) {
                if category.measuresBytes && summary.reclaimableBytes > 0 {
                    Text(Bytes.string(summary.reclaimableBytes))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(category.tint)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        default:
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

extension View {
    /// Shows or hides a layer that shares its slot with others, blurring as it fades.
    ///
    /// A plain cross-fade between two lines of text overlaps them at half opacity, and for
    /// a moment reads as a jumble of both. Blurring the outgoing one makes the swap read
    /// as one line turning into the next.
    func morph(visible: Bool) -> some View {
        self
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 6)
            .scaleEffect(visible ? 1 : 0.97)
    }
}
