import SwiftUI
import AVKit
import Photos

/// Videos, largest first, each with a preview you can play before deciding.
struct LargeVideosView: View {
    let videos: [PhotoAsset]

    @Environment(CleanupSelection.self) private var selection
    @Environment(Navigator.self) private var navigator
    @State private var previewing: PhotoAsset?

    var body: some View {
        Group {
            if videos.isEmpty {
                ContentUnavailableView("No videos", systemImage: "film.stack",
                                       description: Text("There are no videos in your library."))
            } else {
                List {
                    Section {
                        ForEach(videos) { video in
                            VideoRow(
                                video: video,
                                isSelected: selection.isSelected(video.id, in: .largeVideos),
                                onToggle: { selection.toggle(video, in: .largeVideos) },
                                onPreview: { previewing = video }
                            )
                        }
                    } header: {
                        Text("\(videos.count) videos · \(Bytes.string(videos.reduce(0) { $0 + $1.bytes })) total")
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Large Videos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !videos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Route.quickReview(.largeVideos)) {
                        Label("Quick Review", systemImage: "rectangle.stack")
                    }
                }
            }
        }
        .selectionBar(count: selection.count(in: .largeVideos),
                      bytes: selection.bytes(in: .largeVideos)) { navigator.push(.review) }
        .sheet(item: $previewing) { VideoPreviewSheet(asset: $0) }
    }
}

private struct VideoRow: View {
    let video: PhotoAsset
    let isSelected: Bool
    let onToggle: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.danger : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isSelected)

            // The row has its own selection circle; the tile's would be a second, dead one.
            AssetThumbnailView(asset: video, side: 64, isSelected: false, showsChrome: false,
                               onTap: onPreview)

            VStack(alignment: .leading, spacing: 3) {
                Text(Bytes.string(video.bytes))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(AssetThumbnailView.duration(video.duration))
                    if let date = video.creationDate {
                        Text("·")
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.videos)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }
}

/// Plays the video straight from the library. Network access is allowed *here* (unlike
/// during scanning) because the user explicitly asked to watch this one item.
private struct VideoPreviewSheet: View {
    let asset: PhotoAsset
    @State private var player: AVPlayer?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else {
                    ProgressView("Loading video…")
                }
            }
            .navigationTitle(Bytes.string(asset.bytes))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    private func load() async {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic

        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset.phAsset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
        if let item { player = AVPlayer(playerItem: item) }
    }
}
