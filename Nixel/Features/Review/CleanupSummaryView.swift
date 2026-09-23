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
    @Environment(Navigator.self) private var navigator
    @Environment(CleanupSelection.self) private var selection
    @State private var appeared = false
    @State private var shownBytes: Int64 = 0

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
                    Text(Bytes.string(shownBytes))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(shownBytes)))
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
        // Going "back" from here would land on a review screen listing items that are
        // already gone, so the only exit is forward, to the dashboard.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { finish() }
                    .font(.body.weight(.semibold))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: finish) {
                Text("Back to Nixel")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.sm)
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            appeared = true
            scanner.refreshStorage()
        }
        .task {
            // Count up to the total, so the number lands rather than just appearing.
            let steps = 14
            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 45_000_000)
                withAnimation(.snappy(duration: 0.12)) {
                    shownBytes = summary.bytes * Int64(step) / Int64(steps)
                }
            }
        }
    }

    /// Clears what was just removed and returns to the dashboard.
    private func finish() {
        selection.clearAll()
        scanner.refreshStorage()
        navigator.popToRoot()
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
