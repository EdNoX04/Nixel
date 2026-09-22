#if DEBUG
import Foundation
import Photos
import ImageIO

/// Loads a set of stand-in photos and videos into the library for demos and device tests.
///
/// Debug builds only. It exists so the app can be recorded and tested on a real iPhone
/// without anyone's own photos ever appearing on screen: grant Nixel *limited* access with
/// nothing selected, import this set, and iOS lets the app see only the assets it created
/// itself. The personal library stays invisible to it.
///
/// Every created asset's identifier is written to a manifest, so `removeAll()` deletes
/// exactly what was imported and nothing else. That matters because the imports carry
/// their original capture dates — months back — and would otherwise be scattered through
/// the owner's timeline with no easy way to find them again.
enum DemoLibrary {

    /// Pushed here from the Mac with `devicectl device copy to`.
    static var sourceFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DemoLibrary", isDirectory: true)
    }

    private static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-manifest.json")
    }

    private static let imageTypes: Set<String> = ["jpg", "jpeg", "png", "heic"]
    private static let videoTypes: Set<String> = ["mp4", "mov", "m4v"]

    static func availableFiles() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: sourceFolder, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { imageTypes.contains($0.pathExtension.lowercased())
                   || videoTypes.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var importedCount: Int { loadManifest().count }

    // MARK: Import

    /// Imports every file in the source folder. Returns how many assets were created.
    @discardableResult
    static func importAll(progress: @escaping @Sendable (Int, Int) -> Void) async throws -> Int {
        let files = availableFiles()
        guard !files.isEmpty else { return 0 }

        var created = loadManifest()
        var done = 0

        // Chunked: one transaction per file is slow, and one for everything holds several
        // hundred megabytes in a single change the user cannot see progress on.
        for chunk in stride(from: 0, to: files.count, by: 20).map({
            Array(files[$0..<min($0 + 20, files.count)])
        }) {
            let box = PlaceholderBox()
            try await PHPhotoLibrary.shared().performChanges {
                for (offset, url) in chunk.enumerated() {
                    let isVideo = videoTypes.contains(url.pathExtension.lowercased())
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                    // Keep the original capture time: the matcher leans on time order to
                    // find bursts, so imports all stamped "now" would group badly.
                    request.creationDate = captureDate(of: url)
                        ?? Date().addingTimeInterval(-Double(done + offset) * 3_600)
                    if let placeholder = request.placeholderForCreatedAsset {
                        box.append(placeholder.localIdentifier)
                    }
                }
            }
            created += box.identifiers
            done += chunk.count
            saveManifest(created)
            progress(done, files.count)
        }
        return done
    }

    // MARK: Removal

    /// Deletes exactly the assets this importer created. Goes through iOS's own delete
    /// confirmation like any other deletion in the app.
    @discardableResult
    static func removeAll() async throws -> Int {
        let identifiers = loadManifest()
        guard !identifiers.isEmpty else { return 0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        let count = assets.count
        guard count > 0 else { saveManifest([]); return 0 }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        saveManifest([])
        return count
    }

    // MARK: Helpers

    private static func captureDate(of url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: stamp)
    }

    private static func loadManifest() -> [String] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private static func saveManifest(_ identifiers: [String]) {
        try? FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(identifiers) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}

/// Collects placeholder identifiers from inside a `performChanges` block, which runs on a
/// Photos-owned queue.
private final class PlaceholderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    func append(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
    var identifiers: [String] { lock.lock(); defer { lock.unlock() }; return ids }
}
#endif
