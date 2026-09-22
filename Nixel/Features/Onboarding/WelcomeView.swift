import SwiftUI
import AuthenticationServices

/// The welcome screen.
///
/// Signing in is offered, never required: the brief puts login out of scope and the app
/// works entirely on-device, so "Continue without an account" is a first-class route rather
/// than fine print. Nothing in Nixel is gated behind an identity.
struct WelcomeView: View {
    @Environment(AccountStore.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    @State private var panelUp = false
    @State private var markIn = false
    @State private var showEmail = false
    @State private var email = ""
    @State private var message: String?

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
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.19, blue: 0.62),
                Color(red: 0.16, green: 0.30, blue: 0.58),
                Color(red: 0.03, green: 0.38, blue: 0.38)
            ],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: Mark

    private var mark: some View {
        VStack(spacing: Theme.Space.lg) {
            // The icon's cascade, at rest.
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(0..<4) { index in
                    let side = 34 - CGFloat(index) * 7
                    RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                        .fill(.white.opacity(1 - Double(index) * 0.24))
                        .frame(width: side, height: side)
                        .offset(y: markIn ? 0 : 26)
                        .opacity(markIn ? 1 : 0)
                        .animation(
                            .spring(response: 0.6, dampingFraction: 0.7)
                            .delay(Double(index) * 0.07),
                            value: markIn
                        )
                }
            }

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

    private var panel: some View {
        VStack(spacing: Theme.Space.md) {
            if showEmail {
                emailField
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    message = account.handleApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .clipShape(Capsule())

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showEmail = true
                    }
                } label: {
                    Label("Continue with Email", systemImage: "envelope.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Capsule().fill(.white.opacity(0.16)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.sm)
            }

            Button {
                account.signIn(.anonymous)
            } label: {
                Text("Continue without an account")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)

            Text("Nixel works entirely on your iPhone. Signing in is optional and unlocks nothing — your photos and contacts never leave the device either way.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Space.sm)
                .padding(.top, 2)
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

    private var emailField: some View {
        VStack(spacing: Theme.Space.sm) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 50)
                .background(Capsule().fill(.white.opacity(0.16)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))

            Button {
                let trimmed = email.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains("@"), trimmed.count > 3 else {
                    message = "That doesn't look like an email address."
                    return
                }
                account.signIn(.email(trimmed))
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(Color(red: 0.16, green: 0.14, blue: 0.42))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)

            Button("Back") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showEmail = false
                    message = nil
                }
            }
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.7))
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
