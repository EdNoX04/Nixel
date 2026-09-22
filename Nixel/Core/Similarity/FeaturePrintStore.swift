import Foundation

/// On-disk cache of Vision feature prints, keyed by asset id.
///
/// This is what makes a second scan feel instant. Generating a feature print means
/// decoding a thumbnail and running a neural net; comparing two prints is arithmetic on
/// 768 floats. By persisting the expensive half we only ever pay it once per photo, and a
/// rescan of an unchanged library does no Vision work at all.
///
/// Entries are invalidated by the asset's modification date, so an edited photo is
/// re-analysed rather than matched on stale data.
final class FeaturePrintStore {

    struct Record {
        var modified: Double
        var kind: DescriptorKind
        var sharpness: Double
        var people: Int
        var vector: [Float]
    }

    private(set) var records: [String: Record] = [:]
    private var dirty = false
    private let url: URL

    private static let magic: UInt32 = 0x52434650      // "RCFP"
    private static let version: UInt32 = 5

    init(filename: String = "featureprints.bin") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(filename)
        load()
    }

    // MARK: Access

    func record(for id: String, modified: Date?) -> Record? {
        guard let record = records[id] else { return nil }
        guard record.modified == (modified?.timeIntervalSince1970 ?? 0) else { return nil }
        return record
    }

    func store(_ descriptor: Descriptor?, sharpness: Double, people: Int,
               for id: String, modified: Date?) {
        records[id] = Record(modified: modified?.timeIntervalSince1970 ?? 0,
                             kind: descriptor?.kind ?? .vision,
                             sharpness: sharpness,
                             people: people,
                             vector: descriptor?.vector ?? [])
        dirty = true
    }

    /// Drop cache entries for assets that no longer exist, so the file cannot grow forever.
    func prune(keeping liveIDs: Set<String>) {
        let before = records.count
        records = records.filter { liveIDs.contains($0.key) }
        if records.count != before { dirty = true }
    }

    // MARK: Persistence

    func load() {
        guard let data = try? Data(contentsOf: url), data.count > 12 else { return }
        var cursor = 0

        func read<T>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard cursor + size <= data.count else { return nil }
            let value = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: cursor, as: T.self) }
            cursor += size
            return value
        }

        guard let magic = read(UInt32.self), magic == Self.magic,
              let version = read(UInt32.self), version == Self.version,
              let count = read(UInt32.self) else { return }

        var loaded: [String: Record] = [:]
        loaded.reserveCapacity(Int(count))

        for _ in 0..<count {
            guard let idLength = read(UInt16.self),
                  cursor + Int(idLength) <= data.count else { break }
            let id = String(decoding: data[data.startIndex + cursor ..< data.startIndex + cursor + Int(idLength)],
                            as: UTF8.self)
            cursor += Int(idLength)

            guard let modified = read(Double.self),
                  let rawKind = read(UInt16.self),
                  let sharpness = read(Double.self),
                  let people = read(UInt16.self),
                  let dimensions = read(UInt16.self) else { break }
            let kind = DescriptorKind(rawValue: rawKind) ?? .vision

            let byteCount = Int(dimensions) * MemoryLayout<Float>.size
            guard cursor + byteCount <= data.count else { break }
            let vector = data.withUnsafeBytes { raw -> [Float] in
                let base = raw.baseAddress!.advanced(by: cursor)
                let buffer = UnsafeRawBufferPointer(start: base, count: byteCount)
                return Array(buffer.bindMemory(to: Float.self))
            }
            cursor += byteCount

            loaded[id] = Record(modified: modified, kind: kind, sharpness: sharpness,
                                people: Int(people), vector: vector)
        }

        records = loaded
    }

    func save() {
        guard dirty else { return }
        var data = Data()
        withUnsafeBytes(of: Self.magic) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: Self.version) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(records.count)) { data.append(contentsOf: $0) }

        for (id, record) in records {
            let idBytes = Array(id.utf8)
            withUnsafeBytes(of: UInt16(idBytes.count)) { data.append(contentsOf: $0) }
            data.append(contentsOf: idBytes)
            withUnsafeBytes(of: record.modified) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: record.kind.rawValue) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: record.sharpness) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(min(record.people, 65_535))) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(record.vector.count)) { data.append(contentsOf: $0) }
            record.vector.withUnsafeBufferPointer { buffer in
                data.append(UnsafeRawBufferPointer(buffer).bindMemory(to: UInt8.self))
            }
        }

        try? data.write(to: url, options: .atomic)
        dirty = false
    }
}
