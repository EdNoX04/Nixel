import SwiftUI

/// Placeholder until the contacts engine lands in the next pass.
struct DuplicateContactsView: View {
    var body: some View {
        ContentUnavailableView(
            "Coming next",
            systemImage: "person.2",
            description: Text("Duplicate contact detection is being wired up.")
        )
        .navigationTitle("Duplicate Contacts")
        .navigationBarTitleDisplayMode(.inline)
    }
}
