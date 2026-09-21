import Foundation
import BackgroundTasks
import UserNotifications
import Photos

/// The daily agent.
///
/// ## What it can and cannot do
///
/// iOS never lets an app delete photos unattended: `PHAssetChangeRequest.deleteAssets`
/// always raises a system confirmation sheet that needs a foreground tap, and no
/// entitlement removes it. So the agent does not — and cannot — clean automatically.
///
/// What it *can* do is every other part of the job. Once a day, while the phone is idle,
/// it wakes up, scans whatever arrived since last time, runs on-device intelligence over
/// the new screenshots, and assembles a finished cleanup proposal. By the time the user
/// opens the notification, all the work is done and one tap approves it.
///
/// That split is deliberate rather than a limitation we worked around: the whole product
/// promise is that nothing disappears without the owner seeing it first.
@Observable
@MainActor
final class NixelAgent {

    static let shared = NixelAgent()

    static let taskIdentifier = "com.nilabha.nixel.dailyscan"

    private let defaults = UserDefaults.standard
    private let enabledKey = "agent.enabled"
    private let lastRunKey = "agent.lastRun"
    private let lastFindingKey = "agent.lastFinding"

    // MARK: State

    var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set {
            defaults.set(newValue, forKey: enabledKey)
            if newValue { scheduleNextRun() } else { cancelScheduledRuns() }
        }
    }

    /// Stored rather than computed: @Observable can only track stored properties, and
    /// the dashboard needs to update the moment a run finishes.
    private(set) var lastRun: Date?

    /// The last proposal the agent produced, shown on the dashboard.
    struct Finding: Codable, Equatable {
        var duplicates: Int
        var screenshots: Int
        var videos: Int
        var bytes: Int64
        var headline: String
        var date: Date
    }

    private(set) var lastFinding: Finding?

    private init() {
        lastRun = defaults.object(forKey: lastRunKey) as? Date
        if let data = defaults.data(forKey: lastFindingKey) {
            lastFinding = try? JSONDecoder().decode(Finding.self, from: data)
        }
    }

    private func persist(_ finding: Finding?, at date: Date) {
        lastRun = date
        lastFinding = finding
        defaults.set(date, forKey: lastRunKey)
        defaults.set(finding.flatMap { try? JSONEncoder().encode($0) }, forKey: lastFindingKey)
    }

    // MARK: Registration

    /// Must be called before the app finishes launching, or BGTaskScheduler traps.
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let task = task as? BGProcessingTask else { return }
            Task { @MainActor in
                await self.run(task: task)
            }
        }
    }

    func scheduleNextRun() {
        guard isEnabled else { return }
        cancelScheduledRuns()

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        // Scanning a photo library is heavy, so ask iOS to wait for power. It also means
        // we never spend the user's battery on housekeeping.
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = false
        request.earliestBeginDate = Calendar.current.date(byAdding: .hour, value: 20, to: Date())

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Submission fails on simulators and when the user has background refresh off.
            // Neither is worth surfacing: the in-app scan still works.
        }
    }

    func cancelScheduledRuns() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
    }

    // MARK: Permissions

    func requestNotificationPermission() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let granted = try? await centre.requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    // MARK: The run

    private func run(task: BGProcessingTask) async {
        // Always reschedule first: if the work below is killed we still want tomorrow's run.
        scheduleNextRun()

        let work = Task { await performScan() }
        task.expirationHandler = { work.cancel() }

        let finding = await work.value
        task.setTaskCompleted(success: finding != nil)
    }

    /// Runs the same scan the app runs, then narrates it.
    @discardableResult
    func performScan() async -> Finding? {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) != .denied else { return nil }

        let coordinator = ScanCoordinator()
        await coordinator.scanForAgent()

        let duplicates = coordinator.summary(.similarPhotos).itemCount
        let screenshots = coordinator.summary(.screenshots).itemCount
        let videos = coordinator.summary(.largeVideos).itemCount
        let bytes = coordinator.totalReclaimable

        guard bytes > 0 else {
            persist(nil, at: Date())
            return nil
        }

        // Ask Apple Intelligence to phrase it; fall back to a plain sentence if the model
        // isn't available, so the feature still works on every device.
        let headline = await IntelligenceService.shared.summarise(
            duplicates: duplicates, screenshots: screenshots, videos: videos, bytes: bytes
        ) ?? "\(Bytes.string(bytes)) can be freed from \(duplicates + screenshots + videos) items."

        let finding = Finding(duplicates: duplicates, screenshots: screenshots, videos: videos,
                              bytes: bytes, headline: headline, date: Date())

        persist(finding, at: Date())
        await notify(about: finding)
        return finding
    }

    private func notify(about finding: Finding) async {
        let content = UNMutableNotificationContent()
        content.title = "\(Bytes.string(finding.bytes)) ready to clear"
        content.body = finding.headline
        content.sound = .default
        // Deliberately not "cleaned N items": nothing has been touched yet.
        content.userInfo = ["agent": true]

        let request = UNNotificationRequest(
            identifier: "nixel.agent.\(Int(finding.date.timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await UNUserNotificationCenter.current().add(request)
    }
}
