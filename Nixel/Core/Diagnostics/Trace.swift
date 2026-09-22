import Foundation

/// Breadcrumb for device diagnostics. Compiles to nothing in release builds.
@inline(__always)
func trace(_ message: @autoclosure () -> String) {
    #if DEBUG
    Trace.log(message())
    #endif
}

#if DEBUG

/// Timestamped breadcrumbs for diagnosing scans on a real device.
///
/// Written to `scan-trace.log` in Application Support and pulled off the phone with
/// `devicectl`. Step names and counts only — never a file name, a date from a photo, or
/// anything else that describes what is in someone's library.
enum Trace {
    private static let queue = DispatchQueue(label: "nixel.trace")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scan-trace.log")
    }

    static func reset() {
        queue.sync {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? Data().write(to: url)
        }
    }

    static func log(_ message: String) {
        let thread = Thread.isMainThread ? "main" : "bg  "
        let line = "\(formatter.string(from: Date())) [\(thread)] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// Detects a blocked main thread and says so in the trace.
///
/// A background timer asks the main thread to acknowledge every 250ms. If the
/// acknowledgement is more than a second late, the main thread is stuck, and the trace
/// records how long — which is the difference between "the UI froze" and "the scan
/// stalled while the UI stayed responsive".
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "nixel.watchdog")
    private var timer: DispatchSourceTimer?
    private var lastAck = Date()
    private var reportedStall = false
    private let lock = NSLock()

    func start() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 0.25, repeating: 0.25)
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    /// Called on return to the foreground. While suspended the main thread cannot answer,
    /// and that silence is not a hang — without this the first tick after waking would
    /// report the whole time the phone was locked.
    func resetClock() {
        lock.lock(); lastAck = Date(); reportedStall = false; lock.unlock()
    }

    private func tick() {
        lock.lock()
        let silence = Date().timeIntervalSince(lastAck)
        let alreadyReported = reportedStall
        lock.unlock()

        if silence > 1.0 && !alreadyReported {
            Trace.log(String(format: "WATCHDOG main thread unresponsive for %.1fs", silence))
            lock.lock(); reportedStall = true; lock.unlock()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stalled = Date().timeIntervalSince(self.lastAck)
            let wasReported = self.reportedStall
            self.lastAck = Date()
            self.reportedStall = false
            self.lock.unlock()
            if wasReported {
                Trace.log(String(format: "WATCHDOG main thread recovered after %.1fs", stalled))
            }
        }
    }
}
#endif
