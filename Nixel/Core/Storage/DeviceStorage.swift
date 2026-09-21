import Foundation

/// A snapshot of the device's disk usage.
struct StorageSnapshot: Equatable {
    var total: Int64
    var available: Int64

    var used: Int64 { max(0, total - available) }
    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    static let empty = StorageSnapshot(total: 0, available: 0)
}

enum DeviceStorage {

    /// Reads volume capacity for the home directory's volume.
    ///
    /// Note on which "available" figure to use: `volumeAvailableCapacity` reports only
    /// genuinely free bytes, while `volumeAvailableCapacityForImportantUsage` also counts
    /// space iOS is willing to purge (caches, offloaded iCloud media). The second is much
    /// closer to the number Settings > General > iPhone Storage shows the user, so that is
    /// what we display — with a fallback for the rare case where it is unavailable.
    static func snapshot() -> StorageSnapshot {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return .empty
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let important = values.volumeAvailableCapacityForImportantUsage ?? 0
        let plain = Int64(values.volumeAvailableCapacity ?? 0)
        let available = important > 0 ? Int64(important) : plain

        return StorageSnapshot(total: total, available: min(available, total))
    }
}
