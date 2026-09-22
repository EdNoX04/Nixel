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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .fill(Color(.tertiarySystemFill))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
        .overlay(alignment: .bottomLeading) { durationBadge }
        .overlay(alignment: .topTrailing) { if showsChrome { selectionMark } }
        .overlay(alignment: .topLeading) { bestBadge }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                .strokeBorder(isSelected && showsChrome ? Theme.danger : .clear, lineWidth: 3)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .task(id: asset.id) { load() }
        .onDisappear {
            if let id = requestID { GridThumbnailProvider.shared.cancel(id) }
        }
    }

    private func load() {
        guard image == nil else { return }
        requestID = GridThumbnailProvider.shared.image(for: asset.phAsset, side: side) { result in
            if let result { self.image = result }
        }
    }

    @ViewBuilder
    private var selectionMark: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? Theme.danger : .white.opacity(0.55))
            .shadow(radius: 2)
            .padding(5)
    }

    @ViewBuilder
    private var bestBadge: some View {
        if showsBestBadge {
            Text("BEST")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.success))
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
