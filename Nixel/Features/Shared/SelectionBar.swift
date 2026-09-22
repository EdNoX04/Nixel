import SwiftUI

/// The floating bar that appears once anything is selected.
///
/// It never deletes. It only moves the user forward to the review screen, which is the
/// single place a deletion can start from.
struct SelectionBar: View {
    var count: Int
    var bytes: Int64
    var onReview: () -> Void

    var body: some View {
        GlassGroup(spacing: 14) {
            HStack(spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) selected")
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.numericText())
                    if bytes > 0 {
                        Text("Frees \(Bytes.string(bytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Button(action: onReview) {
                    HStack(spacing: 5) {
                        Text("Review").font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.right").font(.caption.weight(.bold))
                    }
                    .foregroundStyle(Theme.onPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.indigo.gradient))
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, Theme.Space.xl)
            .padding(.trailing, Theme.Space.sm)
            .padding(.vertical, Theme.Space.sm)
            .glassBar(cornerRadius: 30)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.bottom, Theme.Space.sm)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: count)
    }
}

/// Small reusable "Select all / none" header above a grid.
struct GridSectionHeader: View {
    var title: String
    var subtitle: String?
    var allSelected: Bool
    var onToggleAll: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    // The AI label arrives after the group is on screen; fade it in rather
                    // than letting the text jump while the user is scrolling.
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(allSelected ? "Deselect All" : "Select All", action: onToggleAll)
                .font(.subheadline.weight(.medium))
        }
    }
}
