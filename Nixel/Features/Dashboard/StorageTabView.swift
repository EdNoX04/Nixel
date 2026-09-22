import SwiftUI
import Photos

/// The storage tab: the number people opened the app for, given the whole screen.
///
/// The five cleanup surfaces live in the tab bar now, so this screen carries only the
/// headline figure, the primary action, and the things that do not deserve a tab of their
/// own — blurry photos and whatever the daily agent last turned up.
struct StorageTabView: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(ScanCoordinator.self) private var scanner
    @State private var showAppearance = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            AmbientBackground(isScanning: scanner.isScanning)

            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    StorageHero(
                        snapshot: scanner.storage,
                        reclaimable: scanner.totalReclaimable,
                        isScanning: scanner.isScanning,
                        progress: scanner.overallProgress
                    )
                    .frame(height: 330)
                    .padding(.top, Theme.Space.sm)

                    if scanner.totalReclaimable > 0 && !scanner.isScanning {
                        VStack(spacing: 2) {
                            Text("\(Bytes.string(scanner.totalReclaimable)) can be freed")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(Theme.success)
                            Text("Reviewed by you before anything is removed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    }

                    scanButton.padding(.horizontal, Theme.Space.xl)

                    // Deliberately nothing else. The tab bar already lists every
                    // destination, so repeating them here was saying the same thing twice
                    // and burying the number people opened the app to see.
                    if permissions.photos == .limited { LimitedAccessNotice() }

                    footer
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Nixel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAppearance = true } label: { Image(systemName: "paintpalette") }
                    .accessibilityLabel("Appearance")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AgentSettingsView() } label: { Image(systemName: "sparkles") }
                    .accessibilityLabel("Daily agent")
            }
        }
        .sheet(isPresented: $showAppearance) { AppearanceView() }
        .navigationDestination(for: CleanupCategory.self) { CategoryDetailView(category: $0) }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scanner.isScanning)
        .task {
            if permissions.photos == .notDetermined { await permissions.requestPhotos() }
            if permissions.photos.canScan, scanner.lastScanDate == nil {
                scanner.scanPhotos(access: permissions.photos)
            }
            if permissions.contacts.canScan, scanner.contactGroups.isEmpty {
                scanner.scanContacts(access: permissions.contacts)
            }
        }
    }

    // MARK: Action

    @ViewBuilder
    private var scanButton: some View {
        if !permissions.photos.canScan {
            Button {
                Task {
                    if permissions.photos == .notDetermined {
                        let granted = await permissions.requestPhotos()
                        if granted.canScan { scanner.scanPhotos(access: granted) }
                    } else {
                        permissions.openSettings()
                    }
                }
            } label: {
                Label(permissions.photos == .notDetermined ? "Allow Photo Access" : "Open Settings",
                      systemImage: "lock.open")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        } else if scanner.isScanning {
            Button(role: .cancel) { scanner.cancelScan() } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo, prominent: false))
        } else {
            Button { scanner.scanPhotos(access: permissions.photos) } label: {
                Label(scanner.lastScanDate == nil ? "Scan My iPhone" : "Scan Again",
                      systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Label("Everything stays on your iPhone", systemImage: "lock.shield")
                .font(.caption2).foregroundStyle(.secondary)
            if let date = scanner.lastScanDate {
                Text("Last scan \(date.formatted(date: .omitted, time: .shortened)) · \(scanner.photosAnalysed) photos")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, Theme.Space.sm)
    }
}
