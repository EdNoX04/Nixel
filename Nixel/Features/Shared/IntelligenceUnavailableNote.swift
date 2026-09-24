import SwiftUI

/// Says plainly when Apple Intelligence can't run here, and what that changes.
///
/// On an iPhone without it (older models, iOS below 26, or turned off) the features that
/// use it quietly fall back — screenshots aren't sorted, groups aren't named. Without a
/// word, that just looks like the app doing less than it should. Everything else works the
/// same, and this says so too.
struct IntelligenceUnavailableNote: View {
    /// What this screen would have done with it, e.g. "Screenshots aren't sorted into
    /// receipts, tickets and memes".
    let effect: String

    private var availability: IntelligenceAvailability { IntelligenceService.shared.availability }

    private var title: String {
        switch availability {
        case .notEnabled:    return "Apple Intelligence is turned off"
        case .modelNotReady: return "Apple Intelligence is still getting ready"
        default:             return "Apple Intelligence isn't available on this iPhone"
        }
    }

    var body: some View {
        if IntelligenceService.shared.isResolved && !availability.isAvailable {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                // "sparkles" rather than the Apple Intelligence glyph, which older iOS lacks —
                // and older iOS is exactly where this note shows.
                Image(systemName: "sparkles")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text("\(effect). Everything else works as usual. \(availability.explanation)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
            .accessibilityElement(children: .combine)
        }
    }
}
