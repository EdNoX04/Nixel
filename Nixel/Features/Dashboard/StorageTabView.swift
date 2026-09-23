import SwiftUI
import Photos

/// The storage tab: the number people opened the app for, given the whole screen.
///
/// The five cleanup surfaces live in the tab bar, so listing them here as well said the
/// same thing twice and pushed the headline figure up and out of the way. What remains is
/// the ring, what it means, and the one action — centred, over the ambient backdrop.
struct StorageTabView: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(ScanCoordinator.self) private var scanner
    @Environment(Navigator.self) private var navigator
    @State private var showPrimer = false

    /// A TabView keeps every tab alive, so the animations have to be told when they are
    /// off screen or they keep burning frames three tabs away.
    @Environment(\.scenePhase) private var scenePhase
    private var isVisible: Bool { navigator.selectedTab == .storage && scenePhase == .active }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            AmbientBackground(isScanning: scanner.isScanning, isActive: isVisible)

            // Layout is fixed: nothing is inserted or removed as a scan starts and stops.
            // The first version dropped the headline and the agent card while scanning, so
            // the centred block re-centred and everything below jumped — twice, in quick
            // succession, on a fast scan. Content now swaps inside slots of fixed size.
            VStack(spacing: Theme.Space.xl) {
                if let finding = NixelAgent.shared.lastFinding {
                    AgentFindingCard(finding: finding)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.sm)
                        .opacity(scanner.isScanning ? 0.45 : 1)
                }

                Spacer(minLength: 0)

                StorageHero(
                    snapshot: scanner.storage,
                    reclaimable: scanner.totalReclaimable,
                    isScanning: scanner.isScanning,
                    progress: scanner.overallProgress,
                    isActive: isVisible
                )
                .frame(width: 236, height: 236)

                headline
                    .frame(height: 58)
                    .padding(.horizontal, Theme.Space.xl)

                scanButton
                    .padding(.horizontal, Theme.Space.xxl)

                footer

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Nixel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { navigator.showAppearance = true } label: { Image(systemName: "paintpalette") }
                    .accessibilityLabel("Appearance")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AgentSettingsView() } label: { Image(systemName: "sparkles") }
                    .accessibilityLabel("Daily agent")
            }
        }
        .sheet(isPresented: $showPrimer) {
            PermissionPrimer(
                onContinue: {
                    showPrimer = false
                    Task { await startScan(explained: true) }
                },
                onCancel: { showPrimer = false }
            )
        }
        .task {
            // Launch does nothing on its own: no permission prompt, no scan. The only
            // exception is someone who has already asked for a scan before, whose results
            // are simply refreshed. Contacts are only ever read from the Contacts tab.
            permissions.refresh()
            if scanner.hasConsentedToScan,
               permissions.photos.canScan,
               !scanner.isScanning,
               scanner.lastScanDate == nil {
                scanner.scanPhotos(access: permissions.photos)
            }
        }
    }

    // MARK: Headline

    private enum HeadlineState { case scanning, empty, reclaimable, clean, intro }

    private var headlineState: HeadlineState {
        if scanner.isScanning { return .scanning }
        if scanner.lastScanDate != nil && scanner.photosAnalysed == 0 { return .empty }
        if scanner.totalReclaimable > 0 { return .reclaimable }
        if scanner.lastScanDate != nil { return .clean }
        return .intro
    }

    /// One fixed slot, five states — all present, cross-faded by opacity.
    ///
    /// Views are never inserted or removed here, so there is no transition that can strand
    /// an old state on screen beside a new one.
    private var headline: some View {
        let state = headlineState
        return ZStack {
            VStack(spacing: 2) {
                Text("Looking through your library").font(.headline)
                Text("Everything stays on this iPhone")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .morph(visible: state == .scanning)

            emptyState
                .morph(visible: state == .empty)
                .allowsHitTesting(state == .empty)

            VStack(spacing: 2) {
                Text("\(Bytes.string(scanner.totalReclaimable)) can be freed")
                    .font(.headline)
                    .foregroundStyle(Theme.success)
                    .contentTransition(.numericText())
                Text("Reviewed by you before anything is removed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .morph(visible: state == .reclaimable)

            VStack(spacing: 2) {
                Text("Nothing to clean right now").font(.headline)
                Text("\(scanner.photosAnalysed) photos checked")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .morph(visible: state == .clean)

            Text("See what's taking up space — nothing is removed without you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .morph(visible: state == .intro)
        }
        .animation(.easeInOut(duration: 0.35), value: state)
    }

    /// A scan that could see nothing. Says why instead of silently showing nothing.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(permissions.photos == .limited
                 ? "No photos shared with Nixel yet"
                 : "No photos to check")
                .font(.headline)
            if permissions.photos == .limited {
                Button("Choose Photos") {
                    if let controller = UIApplication.topViewController() {
                        permissions.presentLimitedPicker(from: controller)
                    }
                }
                .font(.caption.weight(.semibold))
            } else {
                Text("Your library is empty.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Action

    @ViewBuilder
    private var scanButton: some View {
        if !permissions.photos.canScan {
            Button {
                if permissions.photos == .notDetermined {
                    showPrimer = true
                } else {
                    permissions.openSettings()
                }
            } label: {
                Label(permissions.photos == .notDetermined ? "Scan My iPhone" : "Open Settings",
                      systemImage: permissions.photos == .notDetermined
                          ? "sparkle.magnifyingglass" : "lock.open")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        } else if scanner.isScanning {
            Button(role: .cancel) { scanner.cancelScan() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo, prominent: false))
        } else if headlineState == .reclaimable, let tab = biggestWin {
            // After a scan the next step is reviewing, not scanning again — so that is
            // what the one big button offers. Rescanning moves to the footer.
            Button { navigator.show(tab) } label: {
                Label("Start with \(tab.category?.title ?? tab.title)", systemImage: "arrow.right")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        } else {
            Button { Task { await startScan() } } label: {
                Label(scanner.lastScanDate == nil ? "Scan My iPhone" : "Scan Again",
                      systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        }
    }

    /// The tab that frees the most. Blurry photos live on the Similar tab.
    private var biggestWin: TabItem? {
        let options: [(TabItem, Int64)] = [
            (.similar, scanner.summary(.similarPhotos).reclaimableBytes
                     + scanner.summary(.blurryPhotos).reclaimableBytes),
            (.screenshots, scanner.summary(.screenshots).reclaimableBytes),
            (.videos, scanner.summary(.largeVideos).reclaimableBytes)
        ]
        return options.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    /// The one route into a scan: an explicit tap.
    ///
    /// On first use the primer explains what is about to be read; only its Continue button
    /// passes `explained`, which is what finally triggers the system prompt.
    private func startScan(explained: Bool = false) async {
        if permissions.photos == .notDetermined {
            guard explained else {
                showPrimer = true
                return
            }
            let access = await permissions.requestPhotos()
            guard access.canScan else { return }
        }
        guard permissions.photos.canScan else { return }
        scanner.hasConsentedToScan = true
        scanner.scanPhotos(access: permissions.photos, restart: true)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Label("Everything stays on your iPhone", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
            // The second line is always laid out, so it appearing after the first scan
            // doesn't shift the centred ring and button up by half a line.
            ZStack {
                if let date = scanner.lastScanDate {
                HStack(spacing: 6) {
                    Text("Last scan \(date.formatted(date: .omitted, time: .shortened)) · \(scanner.photosAnalysed) photos")
                        .foregroundStyle(.tertiary)
                    if headlineState == .reclaimable {
                        Button("Scan again") { Task { await startScan() } }
                            .fontWeight(.semibold)
                            .disabled(scanner.isScanning)
                    }
                }
                .font(.caption2)
                }
                Text(" ").font(.caption2).hidden()
            }
        }
    }
}
