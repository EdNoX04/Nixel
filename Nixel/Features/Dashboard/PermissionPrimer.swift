import SwiftUI

/// Explains what Nixel is about to read, before iOS asks.
///
/// Two reasons this exists rather than firing the system prompt on launch. The prompt
/// arrives stripped of context — a bare "Allow access to your photos?" the moment an app
/// opens is exactly what makes people tap Don't Allow. And a storage cleaner reading an
/// entire photo library is a big ask: the person should decide it on purpose, at the
/// moment they ask for a scan, knowing that Limited is a real option.
struct PermissionPrimer: View {
    var onContinue: () -> Void
    var onCancel: () -> Void

    var body: some View {
        // Scrolls, with the buttons pinned below: at large text sizes the content is
        // taller than the screen and Continue used to end up off it.
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                NotchedMark(side: 54, colour: Theme.indigo)
                    .padding(.top, Theme.Space.xl)
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.sm) {
                    Text("Before Nixel scans")
                        .font(.title2.weight(.bold))
                    Text("iOS will ask for access to your photos. Here's what that's used for.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    row("square.on.square", "Finds duplicates, blurry shots and large videos",
                        "Compares small thumbnails, never full images.")
                    row("lock.shield", "Stays on this iPhone",
                        "Nothing is uploaded. There is no server.")
                    row("hand.raised", "Deletes nothing on its own",
                        "You review every item, and iOS asks you again.")
                    row("photo.badge.checkmark", "Limited access works too",
                        "Choose Limit Access to scan only photos you pick.")
                }
                .padding(.horizontal, Theme.Space.sm)
            }
            .padding(.horizontal, Theme.Space.xl)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Theme.Space.sm) {
                Button(action: onContinue) {
                    Text("Continue")
                }
                .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))

                Button("Not now", action: onCancel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, Theme.Space.sm)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.sm)
            .background(.bar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.indigo)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
