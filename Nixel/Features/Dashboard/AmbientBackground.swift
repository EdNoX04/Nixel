import SwiftUI

/// A full-bleed animated backdrop for the dashboard.
///
/// Three soft colour fields drift on slow, mutually-prime cycles so the composition never
/// visibly repeats, with a scatter of the app's pixel motif floating over them. It picks up
/// whichever palette is active, so the background is part of the theme rather than a fixed
/// decoration.
///
/// Kept deliberately faint. This sits behind real content — storage figures and photo
/// thumbnails — and anything more assertive would fight them. While a scan runs it lifts
/// slightly and speeds up, which reads as the app working without adding a spinner.
struct AmbientBackground: View {
    var isScanning: Bool

    private struct Blob {
        let hue: Int          // index into the palette trio
        let radius: CGFloat
        let ax: Double, ay: Double     // amplitude
        let sx: Double, sy: Double     // speed
        let px: Double, py: Double     // phase
    }

    private static let blobs: [Blob] = [
        Blob(hue: 0, radius: 300, ax: 0.30, ay: 0.20, sx: 0.043, sy: 0.031, px: 0.0, py: 1.1),
        Blob(hue: 1, radius: 260, ax: 0.26, ay: 0.24, sx: 0.029, sy: 0.047, px: 2.2, py: 0.4),
        Blob(hue: 2, radius: 220, ax: 0.22, ay: 0.28, sx: 0.037, sy: 0.023, px: 4.1, py: 3.3)
    ]

    private var tints: [Color] {
        [Theme.indigo, Theme.teal, Theme.success]
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let lift = isScanning ? 1.55 : 1.0
            let rate = isScanning ? 2.6 : 1.0

            ZStack {
                Canvas { context, size in
                    for blob in Self.blobs {
                        let cx = size.width * (0.5 + blob.ax * sin(t * blob.sx * rate + blob.px))
                        let cy = size.height * (0.5 + blob.ay * cos(t * blob.sy * rate + blob.py))
                        let rect = CGRect(x: cx - blob.radius, y: cy - blob.radius,
                                          width: blob.radius * 2, height: blob.radius * 2)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [
                                    tints[blob.hue].opacity(0.22 * lift),
                                    tints[blob.hue].opacity(0)
                                ]),
                                center: CGPoint(x: cx, y: cy),
                                startRadius: 0, endRadius: blob.radius
                            )
                        )
                    }
                }
                .blur(radius: 40)

                driftingPixels(t: t, rate: rate, lift: lift)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// The icon's motif, scattered and rising.
    private func driftingPixels(t: TimeInterval, rate: Double, lift: Double) -> some View {
        Canvas { context, size in
            let count = 22
            for index in 0..<count {
                let seed = Double(index)
                let speed = (0.014 + (seed.truncatingRemainder(dividingBy: 5)) * 0.006) * rate
                let progress = (t * speed + seed * 0.137).truncatingRemainder(dividingBy: 1)

                let x = ((seed * 0.6180339887).truncatingRemainder(dividingBy: 1)
                         + progress * 0.22).truncatingRemainder(dividingBy: 1)
                let y = 1.05 - progress * 1.15
                guard y > -0.08 else { continue }

                // fade in low, fade out high
                let fade = min(1, min(progress * 5, (1 - progress) * 2.4))
                let alpha = 0.16 * lift * fade
                guard alpha > 0.008 else { continue }

                let side = 5 + (seed.truncatingRemainder(dividingBy: 4)) * 4
                let rect = CGRect(x: x * size.width, y: y * size.height, width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: side * 0.28),
                             with: .color(Theme.indigo.opacity(alpha)))
            }
        }
    }
}
