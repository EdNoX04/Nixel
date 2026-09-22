import SwiftUI

/// Controls for the daily agent.
///
/// This screen is unusually explicit about what the agent will *not* do, because the
/// honest answer is the selling point: it does all the work and still cannot delete
/// anything behind your back.
struct AgentSettingsView: View {
    @State private var agent = AgentViewModel()
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        List {
            Section {
                Toggle(isOn: $agent.isEnabled) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Daily scan").font(.body)
                        Text("Once a day, while charging")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.indigo)
            } header: {
                Text("Agent")
            } footer: {
                Text("Nixel wakes up once a day, scans what's new, sorts it with on-device intelligence, and has a cleanup ready for you.")
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scans new photos").font(.subheadline)
                        Text("Only what changed since last time").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sorts screenshots").font(.subheadline)
                        Text("Tells memes from receipts, on device").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prepares the cleanup").font(.subheadline)
                        Text("Ready to approve in one tap").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success) }

                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Never deletes on its own").font(.subheadline)
                        Text("iOS always asks you first — by design").font(.caption).foregroundStyle(.secondary)
                    }
                } icon: { Image(systemName: "hand.raised.fill").foregroundStyle(Theme.indigo) }
            } header: {
                Text("What it does")
            }

            Section {
                HStack {
                    Text("On-device intelligence")
                    Spacer()
                    Text(agent.intelligenceState)
                        .foregroundStyle(agent.intelligenceReady ? Theme.success : .secondary)
                }
                .font(.subheadline)

                if !agent.intelligenceReady {
                    Text(IntelligenceService.shared.availability.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("People detection")
                    Spacer()
                    Text(agent.peopleState)
                        .foregroundStyle(agent.peopleReady ? Theme.success : .secondary)
                }
                .font(.subheadline)

                if !agent.peopleReady {
                    Text("Vision's detectors are neural and don't run in the Simulator. On a real iPhone, photos with people are left out of bulk selections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Last run")
                    Spacer()
                    Text(agent.lastRunText).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } header: {
                Text("Status")
            } footer: {
                Text("Everything runs on this iPhone. No photo, screenshot or contact is ever uploaded.")
            }

            Section {
                Button {
                    Task { await agent.runNow() }
                } label: {
                    HStack {
                        Text(agent.isRunning ? "Scanning…" : "Run a scan now")
                        Spacer()
                        if agent.isRunning { ProgressView().controlSize(.small) }
                    }
                }
                .disabled(agent.isRunning)
            } footer: {
                if let finding = agent.lastFinding {
                    Text("Last found \(Bytes.string(finding.bytes)) across \(finding.duplicates + finding.screenshots + finding.videos) items.")
                }
            }


            #if DEBUG
            Section {
                let files = DemoLibrary.availableFiles().count
                Button {
                    Task { await importDemo() }
                } label: {
                    HStack {
                        Text(agent.demoBusy ? "Importing…" : "Import demo library")
                        Spacer()
                        if agent.demoBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("\(files) files").foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(files == 0 || agent.demoBusy)

                Button("Remove demo library", role: .destructive) {
                    Task { await removeDemo() }
                }
                .disabled(DemoLibrary.importedCount == 0 || agent.demoBusy)

                Button("Reset Nixel data", role: .destructive) {
                    resetAllData()
                }

                Button {
                    Task { await seedContacts() }
                } label: {
                    HStack {
                        Text("Add demo contacts")
                        Spacer()
                        Text("\(DebugContactSeed.fixtures.count) people").foregroundStyle(.secondary)
                    }
                }

                Button("Remove demo contacts", role: .destructive) {
                    let removed = (try? DebugContactSeed.removeSeeded()) ?? 0
                    agent.seedMessage = "Removed \(removed) demo contacts. Nothing else was touched."
                    scanner.scanContacts(access: permissions.contacts)
                }
                .disabled(DebugContactSeed.seededCount == 0)
            } header: {
                Text("Developer")
            } footer: {
                Text(agent.seedMessage ?? "Debug builds only — never shipped. For a private demo, give Nixel limited Photos access with nothing selected, then import: iOS shows the app only the photos it created.")
            }
            #endif
        }
        .navigationTitle("Daily Agent")
        .navigationBarTitleDisplayMode(.inline)
        .task { agent.refresh() }
    }

    #if DEBUG
    private func importDemo() async {
        // The demo library exists so a device can be recorded without its owner's photos
        // on screen. Under full access the scan that follows would read the whole library,
        // defeating the point — so refuse, and say what to change.
        permissions.refresh()
        guard permissions.photos != .full else {
            agent.seedMessage = "Nixel has full access to your photos. For a private demo, set Settings → Privacy & Security → Photos → Nixel to Limited, with nothing selected, then import."
            return
        }
        agent.demoBusy = true
        defer { agent.demoBusy = false }
        do {
            let count = try await DemoLibrary.importAll { done, total in
                Task { @MainActor in agent.seedMessage = "Imported \(done) of \(total)…" }
            }
            agent.seedMessage = "Imported \(count) items. Rescanning…"
            permissions.refresh()
            scanner.hasConsentedToScan = true
            scanner.scanPhotos(access: permissions.photos, restart: true)
        } catch {
            agent.seedMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    /// Deletes everything Nixel has derived from a library — descriptors, screenshot
    /// verdicts, AI group labels, the agent's finding — and forgets consent, so the next
    /// launch behaves like a first launch. The demo manifest is kept, so imported demo items
    /// can still be removed afterwards.
    private func resetAllData() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        for name in ["featureprints.bin", "screenshot-verdicts.json", "group-insights.json"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
        NixelAgent.shared.clear()
        scanner.hasConsentedToScan = false
        scanner.resetResults()
        agent.seedMessage = "All scan data cleared. Nothing derived from your library remains."
    }

    /// Same rule as the photo import: under full access the contacts scan would read the
    /// whole address book, so refuse and explain.
    private func seedContacts() async {
        permissions.refresh()
        if permissions.contacts == .notDetermined {
            _ = await permissions.requestContacts()
        }
        guard permissions.contacts != .full else {
            agent.seedMessage = "Nixel can read all your contacts. For a private demo, set Settings → Privacy & Security → Contacts → Nixel to Limited, with nobody selected, then add the demo contacts."
            return
        }
        guard permissions.contacts.canScan else {
            agent.seedMessage = "Contacts access is off. Allow limited access first."
            return
        }
        do {
            let count = try DebugContactSeed.seed()
            agent.seedMessage = "Added \(count) demo contacts. Rescanning…"
            scanner.scanContacts(access: permissions.contacts)
        } catch {
            agent.seedMessage = "Couldn't add contacts: \(error.localizedDescription)"
        }
    }

    private func removeDemo() async {
        agent.demoBusy = true
        defer { agent.demoBusy = false }
        do {
            let count = try await DemoLibrary.removeAll()
            agent.seedMessage = "Removed \(count) demo items — empty Recently Deleted to finish."
            scanner.scanPhotos(access: permissions.photos)
        } catch {
            agent.seedMessage = "Nothing removed."
        }
    }
    #endif
}

@Observable
@MainActor
final class AgentViewModel {
    var isRunning = false
    var seedMessage: String?
    var demoBusy = false
    var lastFinding: NixelAgent.Finding?

    var isEnabled: Bool {
        get { NixelAgent.shared.isEnabled }
        set {
            if newValue {
                Task {
                    _ = await NixelAgent.shared.requestNotificationPermission()
                    NixelAgent.shared.isEnabled = true
                }
            } else {
                NixelAgent.shared.isEnabled = false
            }
        }
    }

    var intelligenceReady: Bool { IntelligenceService.shared.availability.isAvailable }

    var peopleReady: Bool { PeopleDetector.isAvailable }
    var peopleState: String { PeopleDetector.isAvailable ? "Ready" : "Unavailable here" }

    var intelligenceState: String {
        switch IntelligenceService.shared.availability {
        case .available:         return "Ready"
        case .deviceNotEligible: return "Not supported"
        case .notEnabled:        return "Off"
        case .modelNotReady:     return "Preparing"
        case .osTooOld:          return "Needs iOS 26"
        }
    }

    var lastRunText: String {
        guard let date = NixelAgent.shared.lastRun else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    func refresh() {
        IntelligenceService.shared.refreshAvailability()
        lastFinding = NixelAgent.shared.lastFinding
    }

    func runNow() async {
        isRunning = true
        defer { isRunning = false }
        _ = await NixelAgent.shared.performScan()
        lastFinding = NixelAgent.shared.lastFinding
    }
}
