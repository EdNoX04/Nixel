import SwiftUI

/// What a category tab shows when it has nothing to list *yet*.
///
/// An empty list used to always read "nothing found", which was simply wrong before the
/// first scan, during one, and with Photos access off. Only a finished scan with no
/// findings gets the "nothing here" message; everything else says what's actually going on.
struct ScanPendingView: View {
    let category: CleanupCategory
    /// Shown once a scan has finished and found nothing.
    let emptyTitle: String
    let emptyMessage: String

    @Environment(ScanCoordinator.self) private var scanner
    @Environment(PermissionCenter.self) private var permissions
    @Environment(Navigator.self) private var navigator

    var body: some View {
        switch scanner.summary(category).state {
        case .ready:
            ContentUnavailableView(emptyTitle, systemImage: category.icon,
                                   description: Text(emptyMessage))
        case .scanning:
            VStack(spacing: Theme.Space.md) {
                ProgressView()
                Text("Scanning your library…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .blocked(let reason):
            ContentUnavailableView {
                Label(reason, systemImage: "lock")
            } description: {
                Text("Nixel needs access to your photos to look for \(category.title.lowercased()).")
            } actions: {
                Button("Open Settings") { permissions.openSettings() }
            }
        case .idle:
            ContentUnavailableView {
                Label("Not scanned yet", systemImage: category.icon)
            } description: {
                Text("Scan your library from the Storage tab and \(category.title.lowercased()) will show up here.")
            } actions: {
                Button("Go to Storage") { navigator.show(.storage) }
            }
        }
    }
}
