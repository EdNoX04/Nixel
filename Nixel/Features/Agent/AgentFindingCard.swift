import SwiftUI

/// What the agent turned up on its last run, phrased by the on-device model.
struct AgentFindingCard: View {
    let finding: NixelAgent.Finding

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.indigo)

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.headline)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Found \(finding.date.formatted(.relative(presentation: .named))) · nothing removed yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.indigo.opacity(0.10))
        )
    }
}
