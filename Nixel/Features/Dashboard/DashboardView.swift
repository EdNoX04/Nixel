import SwiftUI
import Photos

struct DashboardView: View {
    @Environment(PermissionCenter.self) private var permissions
    @Environment(ScanCoordinator.self) private var scanner

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.xl) {
                header
                if permissions.photos == .limited {
                    LimitedAccessNotice()
                }
                if let finding = NixelAgent.shared.lastFinding, !scanner.isScanning {
                    AgentFindingCard(finding: finding)
                }
                categories
                footer
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Nixel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AgentSettingsView()
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel("Daily agent")
            }
        }
        .task {
            // Ask once on first launch, then scan straight away if we're allowed.
            if permissions.photos == .notDetermined {
                await permissions.requestPhotos()
            }
            if permissions.photos.canScan, scanner.lastScanDate == nil {
                scanner.scanPhotos(access: permissions.photos)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Theme.Space.lg) {
            StorageRing(snapshot: scanner.storage, reclaimable: scanner.totalReclaimable)
                .frame(width: 210, height: 210)
                .padding(.top, Theme.Space.md)

            if scanner.totalReclaimable > 0 {
                VStack(spacing: 2) {
                    Text("\(Bytes.string(scanner.totalReclaimable)) can be freed")
                        .font(.headline)
                        .foregroundStyle(Theme.success)
                    Text("Reviewed by you before anything is removed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .transition(.opacity)
            }

            scanButton
        }
    }

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
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        } else if scanner.isScanning {
            Button(role: .cancel) {
                scanner.cancelScan()
            } label: {
                Label("Stop Scanning", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo, prominent: false))
        } else {
            Button {
                scanner.scanPhotos(access: permissions.photos)
            } label: {
                Label(scanner.lastScanDate == nil ? "Scan My iPhone" : "Scan Again",
                      systemImage: "sparkle.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GlassActionButtonStyle(tint: Theme.indigo))
        }
    }

    // MARK: Categories

    private var categories: some View {
        VStack(spacing: Theme.Space.md) {
            ForEach(CleanupCategory.allCases) { category in
                NavigationLink(value: category) {
                    CategoryCard(category: category, summary: scanner.summary(category))
                }
                .buttonStyle(.plain)
                .disabled(!scanner.summary(category).hasFindings)
                .opacity(scanner.summary(category).hasFindings ? 1 : 0.65)
            }
        }
        .navigationDestination(for: CleanupCategory.self) { category in
            CategoryDetailView(category: category)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            Label("Everything stays on your iPhone", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let date = scanner.lastScanDate {
                Text("Last scan \(date.formatted(date: .omitted, time: .shortened)) · \(scanner.photosAnalysed) photos analysed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, Theme.Space.sm)
    }
}

/// Shown when the user granted access to only a hand-picked subset of photos.
/// This is a supported mode, not an error — we say what we can see and offer to widen it.
struct LimitedAccessNotice: View {
    @Environment(PermissionCenter.self) private var permissions

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Image(systemName: "photo.badge.checkmark")
                .foregroundStyle(Theme.warning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning selected photos only")
                    .font(.subheadline.weight(.semibold))
                Text("Nixel can see the photos you picked. Choose more to find everything.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Select More Photos") {
                    if let controller = UIApplication.topViewController() {
                        permissions.presentLimitedPicker(from: controller)
                    }
                }
                .font(.caption.weight(.semibold))
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.warning.opacity(0.12))
        )
    }
}

extension UIApplication {
    /// Finds the frontmost view controller — needed because `presentLimitedLibraryPicker`
    /// is UIKit-only and has no SwiftUI equivalent.
    static func topViewController() -> UIViewController? {
        let scene = shared.connectedScenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
