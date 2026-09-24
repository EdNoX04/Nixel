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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var isVisible: Bool { navigator.selectedTab == .storage && scenePhase == .active }
    /// Ambient motion is decoration; with Reduce Motion on it holds still.
    private var animates: Bool { isVisible && !reduceMotion }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            AmbientBackground(isScanning: scanner.isScanning, isActive: animates)

            // Layout is fixed: nothing is inserted or removed as a scan starts and stops.
            // The first version dropped the headline and the agent card while scanning, so
            // the centred block re-centred and everything below jumped — twice, in quick
            // succession, on a fast scan. Content now swaps inside slots of fixed size.
            // Centred when it fits, scrolling when it doesn't (an iPhone SE, larger text).
            // The ring shrinks on short screens so it usually fits without scrolling.
            GeometryReader { proxy in
                let ring = min(236, max(170, proxy.size.height * 0.32))
                ScrollView {
                    VStack(spacing: proxy.size.height < 620 ? Theme.Space.lg : Theme.Space.xl) {
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
                            isActive: animates
                        )
                        .frame(width: ring, height: ring)
                        // The readout lives inside the ring, which can't grow with text size.
                        .dynamicTypeSize(...DynamicTypeSize.xLarge)

                        headline
                            .frame(minHeight: 58)
                            .padding(.horizontal, Theme.Space.xl)

                        breakdown
                            .padding(.horizontal, Theme.Space.lg)

                        scanButton
                            .padding(.horizontal, Theme.Space.xxl)

                        footer

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            }
        }
        // The ring and tiles are a composition; beyond this text size they stop reading as one.
        // The screen scrolls, so larger sizes still fit — they just stop growing here.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
               !scanner.stoppedByUser,
               scanner.lastScanDate == nil {
                scanner.scanPhotos(access: permissions.photos)
            }
            refreshContactsIfAllowed()
        }
    }

    /// Fills in the Contacts tile when access was already given. Never asks — the prompt
    /// only ever comes from the Contacts tab, where the reason is on screen.
    private func refreshContactsIfAllowed() {
        permissions.refresh()
        guard permissions.contacts.canScan,
              !scanner.summary(.duplicateContacts).state.isScanning else { return }
        scanner.scanContacts(access: permissions.contacts)
    }

    // MARK: Per-category breakdown

    /// What each category could free, straight from the home screen — the brief's first
    /// must-have. A fixed slot: it's laid out before the first scan too (invisible), so
    /// results arriving don't push the button down.
    private var breakdown: some View {
        let shown = scanner.lastScanDate != nil && !scanner.isScanning
            && headlineState != .noAccess && headlineState != .empty
        return HStack(spacing: Theme.Space.sm) {
            tile(.similarPhotos, label: "Similar", tab: .similar)
            tile(.screenshots, label: "Screens", tab: .screenshots)
            tile(.largeVideos, label: "Videos", tab: .videos)
            tile(.blurryPhotos, label: "Blurry", tab: .similar, push: .category(.blurryPhotos))
            tile(.duplicateContacts, label: "Contacts", tab: .contacts)
        }
        // Tiles are five abreast, so their text stops growing at xxLarge; beyond that
        // it would only truncate. The row sizes to its content, never overlapping.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .fixedSize(horizontal: false, vertical: true)
        .morph(visible: shown)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .animation(.easeInOut(duration: 0.35), value: shown)
    }

    private func tile(_ category: CleanupCategory, label: String, tab: TabItem,
                      push route: Route? = nil) -> some View {
        let summary = scanner.summary(category)
        let ready: Bool = { if case .ready = summary.state { return true }; return false }()
        let value: String
        if !ready {
            // Contacts are only read from their own tab, so until then there's no figure.
            value = category == .duplicateContacts ? "Check" : "—"
        } else if category.measuresBytes {
            value = summary.reclaimableBytes > 0 ? Bytes.string(summary.reclaimableBytes) : "None"
        } else {
            value = summary.itemCount > 0 ? "\(summary.itemCount) extra" : "None"
        }
        return Button {
            navigator.show(tab)
            if let route { navigator.push(route, on: tab) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: category.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(category.tint)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .fill(Color(.secondarySystemBackground).opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.measuresBytes
                            ? "\(category.title): \(value) can be freed"
                            : "\(category.title): \(value)")
    }

    // MARK: Headline

    private enum HeadlineState { case scanning, empty, reclaimable, clean, intro, noAccess }

    private var headlineState: HeadlineState {
        if permissions.photos == .denied || permissions.photos == .restricted { return .noAccess }
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
                Text("\(scanner.photosAnalysed) photo\(scanner.photosAnalysed == 1 ? "" : "s") checked")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .morph(visible: state == .clean)

            Text("See what's taking up space — nothing is removed without you")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .morph(visible: state == .intro)

            VStack(spacing: 2) {
                Text("Photo access is off").font(.headline)
                Text(permissions.photos == .restricted
                     ? "It's restricted on this iPhone, so Nixel can't scan."
                     : "Allow it in Settings to scan — Limited works too.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .morph(visible: state == .noAccess)
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
                Button("Choose Photos", action: choosePhotos)
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
            Button(role: .cancel) { scanner.stopScan() } label: {
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
        scanner.resumeAfterStop()
        scanner.scanPhotos(access: permissions.photos, restart: true)
        refreshContactsIfAllowed()
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
                    Text("Last scan \(date.formatted(.relative(presentation: .named))) · \(scanner.photosAnalysed) photo\(scanner.photosAnalysed == 1 ? "" : "s")")
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
            // Limited access is a supported mode, not an error: say what Nixel can see and
            // offer to widen it. Only appears or goes when the permission itself changes.
            if permissions.photos == .limited {
                limitedAccessLine
            }
        }
    }

    private var limitedAccessLine: some View {
        let label = Label("Limited access · only the photos you've shared",
                          systemImage: "photo.badge.checkmark")
            .foregroundStyle(.secondary)
        let button = Button("Choose Photos", action: choosePhotos).fontWeight(.semibold)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { label; button }
            VStack(spacing: 2) { label.multilineTextAlignment(.center); button }
        }
        .font(.caption2)
        .padding(.horizontal, Theme.Space.lg)
    }

    /// iOS's picker for which photos Nixel may see. What was picked is scanned straight
    /// away; the fingerprint cache keeps that quick.
    private func choosePhotos() {
        guard let controller = UIApplication.topViewController() else { return }
        permissions.presentLimitedPicker(from: controller) {
            Task { await startScan() }
        }
    }
}
