import SwiftUI

/// A slow-moving blob gradient behind the storage screen.
///
/// On iOS 18 and later this is a `MeshGradient` whose interior control points drift on
/// sine waves of mutually-prime periods, so the shape folds through itself continuously
/// and never visibly loops. Older systems get blurred radial fields.
///
/// ## Making it cheap
///
/// Three things, because an ambient layer that costs frames is worse than no ambient layer:
///
///  * **No blur on the mesh.** A blur over a view whose contents change every frame forces
///    an offscreen render pass 60 times a second. The blur was only there to hide the
///    seams of a 3x3 control grid; a 4x4 grid with `smoothsColors` is smooth by
///    construction, so the filter goes away and the softness stays.
///  * **Display rate, not a fixed cap.** An earlier 30fps cap looked fine on a 60Hz
///    simulator and juddered on a 120Hz ProMotion phone, where each frame was held for four
///    refreshes and the drifting squares visibly stepped. With the blur gone the per-frame
///    cost is small enough to run at whatever the display asks for.
///  * **Paused when it isn't visible.** A `TabView` keeps every tab's view alive, so
///    without this the gradient would keep animating while the user is three tabs away.
struct AmbientBackground: View {
    var isScanning: Bool
    /// False when this tab is not the one on screen.
    var isActive: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var clock = AnimationClock()

    private var tints: [Color] { [Theme.indigo, Theme.teal, Theme.success] }

    /// Light mode needs a good deal more of everything: the palette's light renditions are
    /// darker and less luminous, and an effect tuned against near-black all but vanishes.
    private var isLight: Bool { colorScheme == .light }
    private var meshOpacity: Double { isLight ? 0.68 : 0.40 }
    private var pixelColour: Color { isLight ? Theme.indigo : .white }
    private var pixelOpacity: Double { isLight ? 0.26 : 0.13 }

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { timeline in
            let t = clock.time(at: timeline.date)
            let rate = isScanning ? 2.3 : 1.0
            let lift = isScanning ? 1.4 : 1.0

            ZStack {
                if #available(iOS 18.0, *) {
                    mesh(t: t, rate: rate)
                        .opacity(meshOpacity * lift)
                        .saturation(isLight ? 1.2 : 1.0)
                } else {
                    legacyBlobs(t: t, rate: rate, lift: lift)
                }

                driftingPixels(t: t, rate: rate, lift: lift)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: isActive) { _, active in clock.setActive(active) }
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
        let fade = isLight ? 0.88 : 0.62

        // Built in typed pieces: a single sixteen-element literal mixing corner constants
        // with function calls is more than the type checker will sit through.
        let topRow: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.34, 0), SIMD2(0.67, 0), SIMD2(1, 0)
        ]
        let upperMid: [SIMD2<Float>] = [
            drift(0.0,  0.33, 0.00, 0.10, 0.13, 1.7),
            drift(0.34, 0.33, 0.13, 0.11, 0.09, 3.1),
            drift(0.67, 0.33, 0.12, 0.09, 0.11, 0.6),
            drift(1.0,  0.33, 0.00, 0.10, 0.12, 4.6)
        ]
        let lowerMid: [SIMD2<Float>] = [
            drift(0.0,  0.67, 0.00, 0.09, 0.10, 2.9),
            drift(0.34, 0.67, 0.14, 0.10, 0.12, 5.2),
            drift(0.67, 0.67, 0.11, 0.12, 0.08, 1.1),
            drift(1.0,  0.67, 0.00, 0.09, 0.13, 3.8)
        ]
        let bottomRow: [SIMD2<Float>] = [
            SIMD2(0, 1), SIMD2(0.34, 1), SIMD2(0.67, 1), SIMD2(1, 1)
        ]
        let points: [SIMD2<Float>] = topRow + upperMid + lowerMid + bottomRow

        let swatch: [Color] = [
            a.opacity(0.50), b.opacity(0.34), c.opacity(0.46), a.opacity(0.38),
            c.opacity(0.42), a.opacity(0.62), b.opacity(0.44), c.opacity(0.40),
            b.opacity(0.44), c.opacity(0.38), a.opacity(0.58), b.opacity(0.36),
            a.opacity(0.40), c.opacity(0.44), b.opacity(0.34), a.opacity(0.48)
        ]
        let colours: [Color] = swatch.map { $0.opacity(fade) }

        // 4x4: one more ring of control points than the eye needs, which is what lets the
        // blur go away.
        return MeshGradient(width: 4, height: 4,
                            points: points, colors: colours, smoothsColors: true)
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
                // Radial gradients are soft by definition — no filter needed.
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
    }

    // MARK: Motif

    /// The icon's squares, rising slowly through the gradient.
    private func driftingPixels(t: TimeInterval, rate: Double, lift: Double) -> some View {
        Canvas { context, size in
            for index in 0..<24 {
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
