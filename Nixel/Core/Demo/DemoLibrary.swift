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

    static var importedCount: Int { loadEntries().count }

    /// Files in the folder that have not been imported yet. Importing is idempotent: files
    /// already recorded in the manifest are skipped, so adding more files and importing
    /// again never duplicates what is already in the library.
    static func pendingFiles() -> [URL] {
        let done = Set(loadEntries().map(\.file))
        return availableFiles().filter { !done.contains($0.lastPathComponent) }
    }

    // MARK: Import

    /// Imports every file in the source folder. Returns how many assets were created.
    @discardableResult
    static func importAll(progress: @escaping @Sendable (Int, Int) -> Void) async throws -> Int {
        let files = pendingFiles()
        guard !files.isEmpty else { return 0 }

        var entries = loadEntries()
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
                        box.append(file: url.lastPathComponent, id: placeholder.localIdentifier)
                    }
                }
            }
            entries += box.entries
            done += chunk.count
            saveEntries(entries)
            progress(done, files.count)
        }
        return done
    }

    // MARK: Removal

    /// Deletes exactly the assets this importer created. Goes through iOS's own delete
    /// confirmation like any other deletion in the app.
    @discardableResult
    static func removeAll() async throws -> Int {
        let identifiers = loadEntries().map(\.id)
        guard !identifiers.isEmpty else { return 0 }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        let count = assets.count
        guard count > 0 else { saveEntries([]); return 0 }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        saveEntries([])
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

    struct Entry: Codable, Equatable {
        var file: String
        var id: String
    }

    private static func loadEntries() -> [Entry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        if let entries = try? JSONDecoder().decode([Entry].self, from: data) { return entries }
        // First-version manifests held bare identifiers. That importer created assets in
        // sorted filename order, and every file added since is named to sort after the
        // originals, so the first N sorted names are exactly the N imported files.
        if let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            let names = availableFiles().map(\.lastPathComponent)
            let migrated = identifiers.enumerated().map { index, id in
                Entry(file: index < names.count ? names[index] : "", id: id)
            }
            saveEntries(migrated)
            return migrated
        }
        return []
    }

    private static func saveEntries(_ entries: [Entry]) {
        try? FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }
}

/// Collects what was created from inside a `performChanges` block, which runs on a
/// Photos-owned queue.
private final class PlaceholderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [DemoLibrary.Entry] = []
    func append(file: String, id: String) {
        lock.lock(); collected.append(.init(file: file, id: id)); lock.unlock()
    }
    var entries: [DemoLibrary.Entry] { lock.lock(); defer { lock.unlock() }; return collected }
}
#endif
