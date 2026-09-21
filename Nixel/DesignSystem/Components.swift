import SwiftUI

/// The storage ring on the dashboard.
struct StorageRing: View {
    var snapshot: StorageSnapshot
    /// Space the current scan believes it can free, drawn as a "will be freed" arc.
    var reclaimable: Int64

    private var usedFraction: Double { snapshot.usedFraction }
    private var reclaimFraction: Double {
        guard snapshot.total > 0 else { return 0 }
        return min(usedFraction, Double(reclaimable) / Double(snapshot.total))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 18)

            // used
            Circle()
                .trim(from: 0, to: usedFraction)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // the slice we could give back, drawn at the leading edge of "used"
            if reclaimFraction > 0.001 {
                Circle()
                    .trim(from: max(0, usedFraction - reclaimFraction), to: usedFraction)
                    .stroke(Theme.success, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(Bytes.string(snapshot.available))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("free")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("of \(Bytes.string(snapshot.total))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .animation(.easeOut(duration: 0.5), value: usedFraction)
        .animation(.easeOut(duration: 0.5), value: reclaimFraction)
    }
}

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
