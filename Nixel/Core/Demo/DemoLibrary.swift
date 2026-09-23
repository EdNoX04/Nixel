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

    /// Every media file in the folder and its subfolders. Batches can be pushed as whole
    /// folders, which is far faster than copying a couple of thousand files one by one.
    static func availableFiles() -> [URL] {
        let walker = FileManager.default.enumerator(
            at: sourceFolder, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        let contents = (walker?.allObjects as? [URL]) ?? []
        return contents
            .filter { imageTypes.contains($0.pathExtension.lowercased())
                   || videoTypes.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static var importedCount: Int { loadEntries().count }

    /// Where the demo library stands against the source folder, as Photos sees it.
    struct Status: Equatable {
        var pending = 0     // files in the folder with no asset yet
        var surplus = 0     // extra assets for a file that already has one
        var unknown = 0     // tracked assets whose source file can't be told
        var files = 0       // media files in the folder
    }

    /// Re-derives the manifest from Photos and reports what an import would do.
    /// Does a resource lookup per asset, so call it off the main actor.
    static func status() -> Status {
        let (kept, surplus, unknown) = reconcile()
        saveEntries(kept + surplus + unknown)
        let have = Set(kept.map(\.file))
        let status = Status(
            pending: availableFiles().filter { !have.contains($0.lastPathComponent) }.count,
            surplus: surplus.count,
            unknown: unknown.count,
            files: availableFiles().count)
        writeDiagnostics(status, kept: kept, surplus: surplus)
        return status
    }

    /// Counts plus a few demo file names, so the state can be checked from a Mac before
    /// anything is imported or removed. Only ever names files from the demo folder.
    private static func writeDiagnostics(_ status: Status, kept: [Entry], surplus: [Entry]) {
        let report: [String: Any] = [
            "files": availableFiles().count,
            "kept": kept.count,
            "pending": status.pending,
            "surplus": status.surplus,
            "unknown": status.unknown,
            "keptSample": kept.prefix(3).map(\.file) + kept.suffix(2).map(\.file),
            "surplusSample": surplus.prefix(3).map(\.file)
        ]
        let url = manifestURL.deletingLastPathComponent().appendingPathComponent("demo-status.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Rebuilds the record of what was imported from Photos itself rather than trusting
    /// the manifest. Every asset this importer created still carries the name of the file
    /// it came from (`PHAssetResource.originalFilename`), so an import that ran twice, or
    /// a first-version manifest of bare identifiers, both come out right. The first copy
    /// of each file (in manifest order) is kept; later copies are surplus. Assets deleted
    /// elsewhere drop out.
    private static func reconcile() -> (kept: [Entry], surplus: [Entry], unknown: [Entry]) {
        let ids = loadEntries().map(\.id)
        guard !ids.isEmpty else { return ([], [], []) }
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            .enumerateObjects { asset, _, _ in byID[asset.localIdentifier] = asset }

        var kept: [Entry] = [], surplus: [Entry] = [], unknown: [Entry] = []
        var seen = Set<String>()
        for id in ids {
            guard let asset = byID.removeValue(forKey: id) else { continue }
            let name = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let entry = Entry(file: name, id: id)
            if name.isEmpty { unknown.append(entry) }
            else if seen.insert(name).inserted { kept.append(entry) }
            else { surplus.append(entry) }
        }
        return (kept, surplus, unknown)
    }

    enum ImportError: LocalizedError {
        case unidentified(Int)
        var errorDescription: String? {
            switch self {
            case .unidentified(let count):
                return "\(count) demo items no longer say which file they came from, so importing could duplicate them. Remove the demo library and import again."
            }
        }
    }

    struct ImportResult {
        var added = 0
        var removed = 0
    }

    // MARK: Import

    /// Brings the library to exactly one asset per file in the source folder: surplus
    /// copies are deleted (iOS asks the user to confirm), then missing files are imported.
    /// Only ever deletes assets recorded in this importer's own manifest.
    @discardableResult
    static func importAll(
        onRemoving: @escaping @Sendable (Int) -> Void = { _ in },
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> ImportResult {
        let (kept, surplus, unknown) = reconcile()
        guard unknown.isEmpty else { throw ImportError.unidentified(unknown.count) }
        saveEntries(kept + surplus)

        var result = ImportResult()
        if !surplus.isEmpty {
            onRemoving(surplus.count)
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: surplus.map(\.id), options: nil)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
            saveEntries(kept)
            result.removed = surplus.count
        }

        let have = Set(kept.map(\.file))
        let files = availableFiles().filter { !have.contains($0.lastPathComponent) }
        guard !files.isEmpty else { return result }

        var entries = kept
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
        result.added = done
        return result
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
        // First-version manifests held bare identifiers. Their file names are left blank
        // for `reconcile()` to read back from Photos — guessing them by position went wrong
        // on a phone where the first version had imported the folder twice.
        if let identifiers = try? JSONDecoder().decode([String].self, from: data) {
            return identifiers.map { Entry(file: "", id: $0) }
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
