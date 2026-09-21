import SwiftUI

/// Controls for the daily agent.
///
/// This screen is unusually explicit about what the agent will *not* do, because the
/// honest answer is the selling point: it does all the work and still cannot delete
/// anything behind your back.
struct AgentSettingsView: View {
    @State private var agent = AgentViewModel()

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
        }
        .navigationTitle("Daily Agent")
        .navigationBarTitleDisplayMode(.inline)
        .task { agent.refresh() }
    }
}

@Observable
@MainActor
final class AgentViewModel {
    var isRunning = false
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
