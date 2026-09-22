import SwiftUI

/// The running animation on the welcome screen.
///
/// Small squares drift diagonally, fade as they rise and wrap back around — the icon's
/// dissolve, kept in motion. Deliberately restrained: one shape, one direction, no colour
/// beyond the brand, so it reads as texture rather than decoration.
///
/// Driven by `TimelineView(.animation)` rather than repeating `withAnimation` loops, so
/// every square is a pure function of elapsed time. That means it cannot drift out of sync,
/// costs nothing to interrupt, and stops dead when the view leaves the screen.
struct PixelDriftView: View {

    private struct Particle {
        let origin: CGPoint      // normalised 0...1
        let size: CGFloat
        let speed: CGFloat
        let phase: CGFloat
        let opacity: CGFloat
    }

    /// Fixed seed: the layout should look considered, not random on every launch.
    private static let particles: [Particle] = {
        var rng = SeededGenerator(seed: 42)
        return (0..<26).map { _ in
            Particle(
                origin: CGPoint(x: rng.next(), y: rng.next()),
                size: 6 + rng.next() * 16,
                speed: 0.05 + rng.next() * 0.10,
                phase: rng.next(),
                opacity: 0.18 + rng.next() * 0.5
            )
        }
    }()

    var body: some View {
        // 30fps: the fastest square crosses the screen in about ten seconds.
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                for particle in Self.particles {
                    // Travel 0...1 along the diagonal, wrapping seamlessly.
                    let progress = (CGFloat(t) * particle.speed + particle.phase)
                        .truncatingRemainder(dividingBy: 1)

                    let x = (particle.origin.x + progress * 0.35).truncatingRemainder(dividingBy: 1)
                    let y = particle.origin.y - progress * 0.8

                    guard y > -0.15 else { continue }

                    // Fade in from the bottom, out at the top.
                    let fade = min(1, min(progress * 4, (1 - progress) * 2.2))
                    let alpha = particle.opacity * fade
                    guard alpha > 0.01 else { continue }

                    let rect = CGRect(
                        x: x * size.width,
                        y: y * size.height,
                        width: particle.size,
                        height: particle.size
                    )
                    let path = Path(roundedRect: rect, cornerRadius: particle.size * 0.28)
                    context.fill(path, with: .color(.white.opacity(alpha)))
                }
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

/// Tiny deterministic generator so the particle layout is identical every launch.
private struct SeededGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 2654435761 &+ 1 }

    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat((state >> 33) % 10_000) / 10_000
    }
}
