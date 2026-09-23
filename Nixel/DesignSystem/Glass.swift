import SwiftUI

/// Liquid Glass surfaces, with a graceful path back to iOS 17.
///
/// The app targets iOS 17 (the brief's floor) but runs on iOS 26+ in practice, so glass is
/// applied where it's available and falls back to a material of the same shape elsewhere.
/// Both renditions use identical geometry, so layout never shifts between OS versions —
/// only the surface treatment changes.
extension View {

    /// A floating bar that hovers over content: the selection and delete bars.
    @ViewBuilder
    func glassBar(cornerRadius: CGFloat = 26) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.14), radius: 18, y: 6)
            )
        }
    }

}

/// The app's primary action button. Uses the real glass button style where available.
struct GlassActionButtonStyle: ButtonStyle {
    var tint: Color
    var prominent: Bool = true
    /// Defaults to the palette-aware label colour; destructive buttons pass white.
    var labelColour: Color = Theme.onPrimary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(prominent ? labelColour : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background {
                if prominent {
                    Capsule().fill(tint.gradient)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay {
                Capsule().strokeBorder(.white.opacity(prominent ? 0.22 : 0.10), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Wraps several glass elements so they blend into each other when close, rather than
/// each rendering its own isolated pane. No-op below iOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
