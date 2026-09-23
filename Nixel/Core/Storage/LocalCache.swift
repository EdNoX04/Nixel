import Foundation

extension URL {
    /// Marks a file Nixel can rebuild from the library as not for backup.
    ///
    /// The caches here are derived from the user's photos (fingerprints, sizes, verdicts).
    /// Kept out of iCloud Backup, they never leave the device by that route either, and
    /// they don't take backup space for something a rescan recreates.
    func excludeFromBackup() {
        var url = self
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
