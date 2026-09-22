import Foundation

/// A clock for ambient animations that stops while its view is off screen.
///
/// The storage screen's animations pause when another tab is showing, to save battery.
/// They used to read wall-clock time, though, so on returning every blob and particle
/// snapped to wherever it would have drifted in the meantime — a visible jump each time
/// you switched back. This clock only accumulates time while active, so the motion
/// resumes exactly where it stopped.
///
/// A reference type on purpose: it is advanced from inside `body`, and mutating it must
/// not itself trigger another render.
final class AnimationClock {
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date? = Date()

    func setActive(_ active: Bool, at now: Date = Date()) {
        if active {
            if resumedAt == nil { resumedAt = now }
        } else if let resumed = resumedAt {
            accumulated += now.timeIntervalSince(resumed)
            resumedAt = nil
        }
    }

    /// Seconds of *visible* time elapsed.
    func time(at date: Date) -> TimeInterval {
        guard let resumed = resumedAt else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(resumed))
    }
}
