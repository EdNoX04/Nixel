import SwiftUI

/// The dashboard's centrepiece: the storage ring, with an animation that never stops.
///
/// Two distinct states, deliberately different rather than the same motion sped up:
///
///  * **Idle** — a slow orbit of particles and a breathing glow. Calm, ambient, something
///    to look at without demanding attention.
///  * **Scanning** — a sweep arc rakes around the ring like radar, the glow pulses in
///    time, and the particles accelerate inward. It should be obvious at a glance that
///    work is happening, without reading a word.
///
/// Both run off `TimelineView(.animation)`, so every frame is a pure function of elapsed
/// time: nothing to keep in sync, nothing to tear down, and it stops dead when the view
/// leaves the screen.
struct StorageHero: View {
    var snapshot: StorageSnapshot
    var reclaimable: Int64
    var isScanning: Bool
    var progress: Double        // 0...1 while scanning
    /// False when this tab is not the one on screen.
    var isActive: Bool = true

    private var usedFraction: Double { snapshot.usedFraction }
    private var reclaimFraction: Double {
        guard snapshot.total > 0 else { return 0 }
        return min(usedFraction, Double(reclaimable) / Double(snapshot.total))
    }

    var body: some View {
        TimelineView(.animation(paused: !isActive)) { timeline in
            let t = clock.time(at: timeline.date)

            ZStack {
                aura(t)
                orbit(t)
                ring
                if isScanning { sweep(t) }
                readout
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: isActive) { _, active in clock.setActive(active) }
    }

    // MARK: Ambient glow

    @Environment(\.colorScheme) private var colorScheme
    @State private var clock = AnimationClock()

    private func aura(_ t: TimeInterval) -> some View {
        // Breathing: slow when idle, quicker and stronger while working.
        let speed = isScanning ? 1.9 : 0.55
        let depth = isScanning ? 0.16 : 0.07
        let pulse = 1 + depth * sin(t * speed)

        // A radial gradient is already soft, so the blur it used to carry was pure cost —
        // an offscreen pass every frame to smooth something that was never hard-edged.
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Theme.indigo.opacity(auraStrength),
                        Theme.indigo.opacity(auraStrength * 0.35),
                        .clear
                    ],
                    center: .center, startRadius: 30, endRadius: 200
                )
            )
            .scaleEffect(pulse)
    }

    /// Light surfaces swallow a faint glow, so it needs more presence there.
    private var auraStrength: Double {
        let base = colorScheme == .light ? 0.26 : 0.16
        return isScanning ? base * 1.9 : base
    }

    // MARK: Orbiting particles

    private func orbit(_ t: TimeInterval) -> some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let base = min(size.width, size.height) / 2
            let count = 14

            for index in 0..<count {
                let seed = Double(index)
                let speed = (isScanning ? 0.85 : 0.22) * (1 + seed.truncatingRemainder(dividingBy: 3) * 0.18)
                let angle = t * speed + seed * (.pi * 2 / Double(count))

                // While scanning the particles are drawn inward, as if being gathered up.
                let drift = isScanning
                    ? 0.80 + 0.10 * sin(t * 1.6 + seed)
                    : 1.06 + 0.05 * sin(t * 0.5 + seed)
                let radius = base * drift

                let point = CGPoint(x: centre.x + cos(angle) * radius,
                                    y: centre.y + sin(angle) * radius)
                let side = 3.0 + seed.truncatingRemainder(dividingBy: 4)
                let base = colorScheme == .light ? 0.45 : 0.30
                let alpha = (isScanning ? base * 1.8 : base) * (0.45 + 0.55 * abs(sin(t * 0.7 + seed)))

                let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2,
                                  width: side, height: side)
                context.fill(Path(roundedRect: rect, cornerRadius: side * 0.3),
                             with: .color(Theme.indigo.opacity(alpha)))
            }
        }
    }

    // MARK: The ring itself

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 20)

            Circle()
                .trim(from: 0, to: usedFraction)
                .stroke(Theme.brandGradient, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // The slice we could give back, at the leading edge of "used".
            if reclaimFraction > 0.001 {
                Circle()
                    .trim(from: max(0, usedFraction - reclaimFraction), to: usedFraction)
                    .stroke(Theme.success, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .animation(.easeOut(duration: 0.6), value: usedFraction)
        .animation(.easeOut(duration: 0.6), value: reclaimFraction)
    }

    /// Radar sweep — only while scanning, and unmistakably not the idle motion.
    private func sweep(_ t: TimeInterval) -> some View {
        Circle()
            .trim(from: 0, to: 0.13)
            .stroke(
                AngularGradient(colors: [Theme.indigo.opacity(0), Theme.indigo], center: .center),
                style: StrokeStyle(lineWidth: 20, lineCap: .round)
            )
            .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 2) / 2 * 360))
            .blendMode(.plusLighter)
    }

    // MARK: Numbers

    /// Both readouts are always present and cross-fade by opacity.
    ///
    /// This used to be an if/else with a transition. Inside a `TimelineView` that redraws
    /// every frame, the outgoing view could be stranded mid-fade, leaving "Scanning 4%"
    /// drawn over a ghost of the free-space figure. Nothing is inserted or removed now, so
    /// there is no transition to strand.
    private var readout: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(Bytes.string(snapshot.available))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    // One line, always: the ring shrinks on small iPhones and a wrapped
                    // "42.49 / GB" broke out of it.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 18)
                    .contentTransition(.numericText())
                Text("free")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("of \(Bytes.string(snapshot.total))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 1)
            }
            .morph(visible: !isScanning)

            VStack(spacing: 2) {
                Text("Scanning")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.indigo)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(value: progress))
                    .monospacedDigit()
                    .animation(.easeOut(duration: 0.45), value: Int(progress * 100))
            }
            .morph(visible: isScanning)
        }
        .animation(.easeInOut(duration: 0.3), value: isScanning)
    }
}
