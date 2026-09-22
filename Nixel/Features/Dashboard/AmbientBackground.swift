import SwiftUI

/// A slow-moving blob gradient behind the storage screen.
///
/// On iOS 18 and later this is a `MeshGradient` whose interior control points drift on
/// sine waves of mutually-prime periods, so the shape folds through itself continuously
/// and never visibly loops. Older systems get blurred radial fields, which reads as the
/// same idea with less fidelity.
///
/// Kept faint on purpose. It sits behind real content — a storage figure people are trying
/// to read — so it is tuned to be noticed only once you stop looking at anything else.
/// While a scan runs it lifts and quickens, which signals work without adding a spinner.
struct AmbientBackground: View {
    var isScanning: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var tints: [Color] { [Theme.indigo, Theme.teal, Theme.success] }

    /// Light mode needs a good deal more of everything.
    ///
    /// The first version was tuned against a near-black background and all but vanished on
    /// white: the palette's light renditions are darker and less luminous, and the drifting
    /// squares were filled with white, which is simply invisible on a light surface.
    private var isLight: Bool { colorScheme == .light }
    private var meshOpacity: Double { isLight ? 0.72 : 0.42 }
    private var pixelColour: Color { isLight ? Theme.indigo : .white }
    private var pixelOpacity: Double { isLight ? 0.26 : 0.13 }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let rate = isScanning ? 2.3 : 1.0
            let lift = isScanning ? 1.5 : 1.0

            ZStack {
                if #available(iOS 18.0, *) {
                    mesh(t: t, rate: rate)
                        .opacity(meshOpacity * lift)
                        .blur(radius: isLight ? 34 : 26)
                        .saturation(isLight ? 1.25 : 1.0)
                } else {
                    legacyBlobs(t: t, rate: rate, lift: lift)
                }

                driftingPixels(t: t, rate: rate, lift: lift)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Mesh

    @available(iOS 18.0, *)
    private func mesh(t: TimeInterval, rate: Double) -> some View {
        /// Interior points wander; edge points stay put so the gradient never tears away
        /// from the screen edges.
        func drift(_ x: Float, _ y: Float, _ ax: Float, _ ay: Float,
                   _ speed: Double, _ phase: Double) -> SIMD2<Float> {
            SIMD2(
                x + ax * Float(sin(t * speed * rate + phase)),
                y + ay * Float(cos(t * speed * 0.73 * rate + phase * 1.4))
            )
        }

        let a = tints[0], b = tints[1], c = tints[2]

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2(0, 0),
                drift(0.5, 0.0, 0.14, 0.05, 0.10, 0.0),
                SIMD2(1, 0),

                drift(0.0, 0.5, 0.05, 0.13, 0.13, 1.7),
                drift(0.5, 0.5, 0.20, 0.17, 0.08, 3.1),
                drift(1.0, 0.5, 0.05, 0.13, 0.11, 4.6),

                SIMD2(0, 1),
                drift(0.5, 1.0, 0.14, 0.05, 0.12, 2.4),
                SIMD2(1, 1)
            ],
            colors: [
                a.opacity(0.55), b.opacity(0.35), c.opacity(0.50),
                c.opacity(0.40), a.opacity(0.65), b.opacity(0.45),
                b.opacity(0.45), c.opacity(0.35), a.opacity(0.55)
            ].map { $0.opacity(isLight ? 0.9 : 0.65) },
            smoothsColors: true
        )
    }

    // MARK: Pre-18 fallback

    private func legacyBlobs(t: TimeInterval, rate: Double, lift: Double) -> some View {
        Canvas { context, size in
            let blobs: [(hue: Int, radius: CGFloat, ax: Double, ay: Double,
                         sx: Double, sy: Double, px: Double, py: Double)] = [
                (0, 300, 0.30, 0.20, 0.043, 0.031, 0.0, 1.1),
                (1, 260, 0.26, 0.24, 0.029, 0.047, 2.2, 0.4),
                (2, 220, 0.22, 0.28, 0.037, 0.023, 4.1, 3.3)
            ]
            for blob in blobs {
                let cx = size.width * (0.5 + blob.ax * sin(t * blob.sx * rate + blob.px))
                let cy = size.height * (0.5 + blob.ay * cos(t * blob.sy * rate + blob.py))
                let rect = CGRect(x: cx - blob.radius, y: cy - blob.radius,
                                  width: blob.radius * 2, height: blob.radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [tints[blob.hue].opacity((isLight ? 0.38 : 0.22) * lift),
                                          tints[blob.hue].opacity(0)]),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 0, endRadius: blob.radius)
                )
            }
        }
        .blur(radius: 40)
    }

    // MARK: Motif

    /// The icon's squares, rising slowly through the gradient.
    private func driftingPixels(t: TimeInterval, rate: Double, lift: Double) -> some View {
        Canvas { context, size in
            for index in 0..<26 {
                let seed = Double(index)
                let speed = (0.012 + (seed.truncatingRemainder(dividingBy: 5)) * 0.005) * rate
                let progress = (t * speed + seed * 0.137).truncatingRemainder(dividingBy: 1)

                let x = ((seed * 0.6180339887).truncatingRemainder(dividingBy: 1)
                         + progress * 0.18).truncatingRemainder(dividingBy: 1)
                let y = 1.05 - progress * 1.15
                guard y > -0.08 else { continue }

                let fade = min(1, min(progress * 5, (1 - progress) * 2.4))
                let alpha = pixelOpacity * lift * fade
                guard alpha > 0.008 else { continue }

                let side = 5 + (seed.truncatingRemainder(dividingBy: 4)) * 4
                let rect = CGRect(x: x * size.width, y: y * size.height, width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: side * 0.28),
                             with: .color(pixelColour.opacity(alpha)))
            }
        }
    }
}
