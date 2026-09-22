import Foundation
import CoreGraphics

/// Where all neural work runs. Never on Swift's cooperative thread pool.
///
/// ## The bug this exists to prevent
///
/// Vision's `perform` is synchronous. The scan used to call it from inside a task group,
/// so each in-flight analysis blocked one of the cooperative pool's threads — and that pool
/// is sized to the CPU, about six threads on an iPhone. On device the first requests also
/// cold-load models onto the Neural Engine, which can take a long time, and they were all
/// starting at once: feature prints, face detection, accurate OCR. Every thread ended up
/// waiting on the Neural Engine, nothing else in the app could be scheduled, and the scan
/// sat at 4% indefinitely. Even the six-second request timeouts could not fire their
/// continuations, because there was no thread left to run them on. Cancelling did not help
/// either: cancellation cannot interrupt synchronous code, so the stuck threads stayed stuck
/// and a restarted scan could not even fetch its screenshots.
///
/// Running Vision on its own queue keeps the cooperative pool free. Two at a time is
/// deliberate: the Neural Engine is one shared piece of hardware, so wider concurrency just
/// queues inside it while making contention worse.
enum VisionWork {

    static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "nixel.vision"
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Runs synchronous work on the Vision queue and suspends — rather than blocks — the
    /// caller until it finishes. Operations are never cancelled once queued: each one owns a
    /// continuation that must resume.
    static func run<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.addOperation { continuation.resume(returning: work()) }
        }
    }

    private static let warmLock = NSLock()
    nonisolated(unsafe) private static var warmed = false

    /// Loads the models once, serially, before the parallel pass. Otherwise the first
    /// requests each trigger their own cold load on the Neural Engine simultaneously.
    static func warmUp() async {
        warmLock.lock()
        let already = warmed
        warmed = true
        warmLock.unlock()
        guard !already else { return }

        trace("vision: warming models")
        await run {
            guard let blank = Self.blankImage() else { return }
            _ = DescriptorEngine.compute(for: blank)
            _ = PeopleDetector.count(in: blank)
        }
        trace("vision: warm")
    }

    private static func blankImage(side: Int = 64) -> CGImage? {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return context?.makeImage()
    }
}
