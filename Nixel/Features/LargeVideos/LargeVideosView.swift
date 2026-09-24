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
                ScanPendingView(category: .largeVideos,
                                emptyTitle: "No videos",
                                emptyMessage: "There are no videos in your library.")
            } else {
                // Every video is listed, largest first. Only the large ones count towards
                // "can be freed" on the dashboard, so the two are shown apart.
                let large = videos.filter { $0.bytes >= ScanCoordinator.largeVideoBytes }
                let small = videos.filter { $0.bytes < ScanCoordinator.largeVideoBytes }
                List {
                    if !large.isEmpty {
                        Section {
                            rows(large)
                        } header: {
                            Text("Large · \(Self.summary(large))")
                        } footer: {
                            Text("Videos of \(Bytes.string(ScanCoordinator.largeVideoBytes)) or more. These count towards what Nixel says can be freed.")
                        }
                    }
                    if !small.isEmpty {
                        Section {
                            rows(small)
                        } header: {
                            Text("Smaller videos · \(Self.summary(small))")
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Videos")
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

    @ViewBuilder
    private func rows(_ list: [PhotoAsset]) -> some View {
        ForEach(list) { video in
            VideoRow(
                video: video,
                isSelected: selection.isSelected(video.id, in: .largeVideos),
                onToggle: { selection.toggle(video, in: .largeVideos) },
                onPreview: { previewing = video }
            )
        }
    }

    private static func summary(_ list: [PhotoAsset]) -> String {
        "\(list.count) video\(list.count == 1 ? "" : "s"), \(Bytes.string(list.reduce(0) { $0 + $1.bytes }))"
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
            .accessibilityLabel(isSelected ? "Selected for removal" : "Select for removal")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

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
            .accessibilityLabel("Preview video")
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
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                } else if failed {
                    ContentUnavailableView("Can't play this video",
                                           systemImage: "exclamationmark.icloud",
                                           description: Text("It may only be in iCloud and couldn't be downloaded right now."))
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
        if let item { player = AVPlayer(playerItem: item) } else { failed = true }
    }
}
