import SwiftUI

/// The welcome screen.
///
/// Signing in is offered, never required: the brief puts login out of scope and the app
/// works entirely on-device, so "Continue without an account" is a first-class route rather
/// than fine print. Nothing in Nixel is gated behind an identity.
struct WelcomeView: View {
    @Environment(AccountStore.self) private var account

    @State private var panelUp = false
    @State private var markIn = false

    var body: some View {
        ZStack {
            background
            PixelDriftView()

            VStack(spacing: 0) {
                Spacer()
                mark
                Spacer()
                panel
            }
        }
        .preferredColorScheme(.dark)      // the gradient is a dark surface in both themes
        .task {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) { markIn = true }
            // Let the animation breathe for a beat, then bring the options up.
            try? await Task.sleep(nanoseconds: 550_000_000)
            withAnimation(.spring(response: 0.62, dampingFraction: 0.82)) { panelUp = true }
        }
    }

    // MARK: Background

    private var background: some View {
        Theme.welcomeGradient.ignoresSafeArea()
    }

    // MARK: Mark

    private var mark: some View {
        VStack(spacing: Theme.Space.lg) {
            // The app icon's shape, animated in: a square with a corner taken out and
            // the removed piece set down beside it.
            NotchedMark(side: 74, colour: .white)
                .scaleEffect(markIn ? 1 : 0.82)
                .opacity(markIn ? 1 : 0)
                .animation(.spring(response: 0.62, dampingFraction: 0.68), value: markIn)

            VStack(spacing: 6) {
                Text("Nixel")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Nix the pixels you don't need.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .opacity(markIn ? 1 : 0)
            .offset(y: markIn ? 0 : 14)
        }
    }

    // MARK: Options panel

    // No sign-in. The brief puts login out of scope, and Sign in with Apple needs a
    // capability a free developer account can't provision — the button could only ever
    // fail. The welcome is an introduction and one way forward.
    private var panel: some View {
        VStack(spacing: Theme.Space.md) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                point("sparkle.magnifyingglass", "Finds repeats, screenshots, big videos and blurry shots")
                point("hand.raised.fill", "Nothing is deleted until you review it — and iOS asks too")
                point("lock.shield.fill", "Everything runs on this iPhone. Nothing is uploaded")
            }
            .padding(.bottom, Theme.Space.sm)

            Button {
                account.completeWelcome()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .foregroundStyle(Color(hex: AppPalette.current.spec.primary.light))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.lg)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 30, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: 30,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 30, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 30,
                    style: .continuous
                )
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            )
            .ignoresSafeArea(edges: .bottom)
        )
        // The push-up: the panel starts below the screen and springs into place.
        .offset(y: panelUp ? 0 : 420)
        .opacity(panelUp ? 1 : 0)
    }

    private func point(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline).foregroundStyle(.white.opacity(0.9))
        } icon: {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.75))
        }
    }
}
