import SwiftUI

/// Explains why a "select all" did not select everything.
///
/// Silently skipping photos would be worse than not skipping them: the user would count
/// the selection, find it short, and stop trusting the number. So the brake is stated.
struct PeopleHeldBackNote: View {
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "person.fill.checkmark")
                .foregroundStyle(Theme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) photo\(count == 1 ? "" : "s") with people left out")
                    .font(.subheadline.weight(.semibold))
                Text("Select those individually — a fast tap shouldn't sweep up someone's photo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .fill(Theme.success.opacity(0.12))
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
