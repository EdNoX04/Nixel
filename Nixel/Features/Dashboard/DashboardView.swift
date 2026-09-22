import SwiftUI
import Photos

/// Shown when the user granted access to only a hand-picked subset of photos.
/// This is a supported mode, not an error — we say what we can see and offer to widen it.
struct LimitedAccessNotice: View {
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "photo.badge.checkmark")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning selected photos only")
                    .font(.subheadline.weight(.semibold))
                Text("Nixel can see the photos you picked. Choose more to find everything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select More Photos") {
                    if let controller = UIApplication.topViewController() {
                        permissions.presentLimitedPicker(from: controller)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
        )
    }
}

extension UIApplication {
    /// Finds the frontmost view controller — needed because `presentLimitedLibraryPicker`
    /// is UIKit-only and has no SwiftUI equivalent.
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
