import SwiftUI
import Photos

/// A single photo/video tile that loads its image lazily and cancels cleanly on scroll.
struct AssetThumbnailView: View {
    let asset: PhotoAsset
    var side: CGFloat
    var isSelected: Bool
    var showsBestBadge: Bool = false
    /// Swipe review shows one card at a time, where a selection circle is just noise.
    var showsChrome: Bool = true
    var onTap: () -> Void

    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var taps = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .overlay {
            // A light veil marks the selection on busy photos, where a thin border alone
            // is easy to miss.
            Color.black.opacity(isSelected && showsChrome ? 0.18 : 0)
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
        .overlay(alignment: .bottomLeading) { durationBadge }
        .overlay(alignment: .topTrailing) { if showsChrome { selectionMark } }
        .overlay(alignment: .topLeading) { bestBadge }
        .overlay(alignment: .bottomTrailing) { if showsChrome { peopleBadge } }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .strokeBorder(isSelected && showsChrome ? Theme.danger : .clear, lineWidth: 3)
        }
        .scaleEffect(isSelected && showsChrome ? 0.96 : 1)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            taps += 1
            onTap()
        }
        // On the tap, not on isSelected: a "Select All" flips dozens of tiles at once and
        // should not fire dozens of haptics.
        .sensoryFeedback(.selection, trigger: taps)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected && showsChrome ? .isSelected : [])
        .accessibilityAction {
            taps += 1
            onTap()
        }
        .task(id: asset.id) { load() }
        .onDisappear {
            if let id = requestID { GridThumbnailProvider.shared.cancel(id) }
            requestID = nil
            // Lazy grids keep off-screen cells' state; holding every decoded tile grew
            // without bound on a large library. The image cache makes reloading cheap.
            image = nil
        }
    }

    private var accessibilityDescription: String {
        var parts = [asset.isVideo ? "Video" : (asset.isScreenshot ? "Screenshot" : "Photo")]
        if asset.isVideo, asset.duration > 0 { parts.append(Self.duration(asset.duration)) }
        if let date = asset.creationDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        if asset.bytes > 0 { parts.append(Bytes.string(asset.bytes)) }
        if showsBestBadge { parts.append("best shot, kept") }
        if asset.hasPeople { parts.append("has people") }
        return parts.joined(separator: ", ")
    }

    private func load() {
        guard image == nil else { return }
        let started = Date()
        requestID = GridThumbnailProvider.shared.image(for: asset.phAsset, side: side) { result in
            guard let result else { return }
            // Fade in only what actually had to load; a cache hit on scrolling back
            // appears instantly instead of flashing.
            if Date().timeIntervalSince(started) < 0.05 {
                self.image = result
            } else {
                withAnimation(.easeOut(duration: 0.22)) { self.image = result }
            }
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .contentTransition(.symbolEffect(.replace))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Theme.onDanger : .white,
                             isSelected ? Theme.danger : .white.opacity(0.55))
            .shadow(radius: 2)
            .padding(5)
    }

    @ViewBuilder
    private var bestBadge: some View {
        if showsBestBadge {
            Text("BEST")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Theme.onSuccess)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.success))
                .padding(5)
        }
    }

    /// Marks a photo the bulk actions deliberately skipped.
    @ViewBuilder
    private var peopleBadge: some View {
        if asset.hasPeople {
            Image(systemName: "person.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Circle().fill(.black.opacity(0.55)))
                .padding(5)
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if asset.isVideo, asset.duration > 0 {
            Text(Self.duration(asset.duration))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(5)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
