import SwiftUI
import UIKit

/// Shown after a successful cleanup.
///
/// The honest bit: on iOS, deleting a photo moves it to **Recently Deleted**, where it sits
/// for 30 days. The bytes are not actually returned to the user until that album is
/// emptied, and there is no public API to empty it or even to read it. Most cleaners quietly
/// report the space as already freed. Nixel says what really happened and points the user at
/// the one step that finishes the job — which also matches the brief's rule about not
/// promising things iOS does not allow.
struct CleanupSummaryView: View {
    let summary: CleanupSummary

    @Environment(ScanCoordinator.self) private var scanner
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                Spacer(minLength: Theme.Space.xxl)

                ZStack {
                    Circle()
                        .fill(Theme.success.opacity(0.15))
                        .frame(width: 128, height: 128)
                    Image(systemName: "checkmark")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(Theme.success)
                        .scaleEffect(appeared ? 1 : 0.4)
                        .opacity(appeared ? 1 : 0)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.6), value: appeared)

                VStack(spacing: Theme.Space.xs) {
                    Text(Bytes.string(summary.bytes))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("cleared from \(summary.count) item\(summary.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                recentlyDeletedCard

                Spacer(minLength: Theme.Space.xl)
            }
            .padding(.horizontal, Theme.Space.lg)
        }
        .navigationTitle("Done")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            appeared = true
            scanner.refreshStorage()
        }
    }

    private var recentlyDeletedCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Label("One last step", systemImage: "trash")
                .font(.headline)
                .foregroundStyle(Theme.warning)

            Text("iOS moved these to **Recently Deleted**, where they stay for 30 days. The space comes back once you empty that album.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                // Opens Photos. iOS exposes no deep link to the Recently Deleted album
                // specifically, so we land the user in Photos and tell them where to go.
                if let url = URL(string: "photos-redirect://"), UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Photos", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Text("Albums → Recently Deleted → Select → Delete All")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
        )
    }
}
