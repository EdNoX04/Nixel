import SwiftUI

/// The app's mark, in SwiftUI.
///
/// The same shape as the icon — a rounded square with a bite removed from one corner and
/// the removed piece resting just outside it — so the welcome screen and anywhere else the
/// brand appears stay in step with the icon rather than drifting into a second logo.
struct NotchedMark: View {
    var side: CGFloat
    var colour: Color = .primary

    private var bite: CGFloat { side * 0.43 }
    private var loose: CGFloat { side * 0.30 }
    private var gap: CGFloat { side * 0.065 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Body with the corner subtracted. `.destinationOut` removes the overlapping
            // area outright rather than painting over it, so the mark works on any ground.
            RoundedRectangle(cornerRadius: side * 0.235, style: .continuous)
                .fill(colour)
                .frame(width: side, height: side)
                .overlay(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: bite * 0.34, style: .continuous)
                        .frame(width: bite * 1.3, height: bite * 1.3)
                        .offset(x: bite * 0.30, y: bite * 0.30)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

            RoundedRectangle(cornerRadius: loose * 0.28, style: .continuous)
                .fill(colour)
                .frame(width: loose, height: loose)
                .rotationEffect(.degrees(-13))
                .offset(x: side + gap, y: side - loose * 0.15)
        }
        .frame(width: side + gap + loose, height: side + loose * 0.4, alignment: .topLeading)
    }
}
