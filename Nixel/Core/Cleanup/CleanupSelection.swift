import Foundation
import SwiftUI

/// Everything the user has marked for removal, across every category.
///
/// Selection is deliberately app-wide rather than per-screen: the review step has to show
/// one honest total, and a user who selects videos, backs out, then selects screenshots
/// should still see both counted.
///
/// Nothing in here deletes anything. It is a shopping list, and the only code that acts on
/// it is `CleanupRunner`, after an explicit confirmation.
@Observable
@MainActor
final class CleanupSelection {

    private(set) var assets: [CleanupCategory: Set<String>] = [:]
    /// Byte size per asset id, captured at selection time so totals never need a re-lookup.
    private var sizes: [String: Int64] = [:]
    /// The `PHAsset`-backed items, kept so the review screen can show thumbnails.
    private var items: [String: PhotoAsset] = [:]

    // MARK: Queries

    func isSelected(_ id: String, in category: CleanupCategory) -> Bool {
        assets[category]?.contains(id) ?? false
    }

    func count(in category: CleanupCategory) -> Int {
        assets[category]?.count ?? 0
    }

    func bytes(in category: CleanupCategory) -> Int64 {
        (assets[category] ?? []).reduce(0) { $0 + (sizes[$1] ?? 0) }
    }

    /// Everything selected, counted once even if picked in two categories.
    private var allIDs: Set<String> { assets.values.reduce(into: Set<String>()) { $0.formUnion($1) } }

    var totalCount: Int { allIDs.count }

    var totalBytes: Int64 { allIDs.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) } }

    var isEmpty: Bool { totalCount == 0 }

    /// All selected photo assets, grouped by category, for the review screen.
    func selectedItems(in category: CleanupCategory) -> [PhotoAsset] {
        (assets[category] ?? []).compactMap { items[$0] }
            .sorted { $0.bytes > $1.bytes }
    }

    var allSelectedAssets: [PhotoAsset] {
        allIDs.compactMap { items[$0] }
    }

    // MARK: Mutation

    func toggle(_ asset: PhotoAsset, in category: CleanupCategory) {
        var set = assets[category] ?? []
        if set.contains(asset.id) {
            set.remove(asset.id)
        } else {
            set.insert(asset.id)
            sizes[asset.id] = asset.bytes
            items[asset.id] = asset
        }
        assets[category] = set
    }

    /// Bulk selection, minus anything with a person in it and anything marked a favourite.
    ///
    /// A tap that selects two hundred photos at once is exactly where an irreplaceable
    /// one gets swept up. Those are left for the user to pick individually; the screens
    /// that call this say so rather than silently skipping them. Returns how many were
    /// held back.
    @discardableResult
    func selectSkippingPeople(_ list: [PhotoAsset], in category: CleanupCategory) -> Int {
        let safe = Self.bulkSelectable(list)
        select(safe, in: category)
        return list.count - safe.count
    }

    /// What a bulk action may take from `list`: everything but photos that might show a
    /// person and favourites.
    static func bulkSelectable(_ list: [PhotoAsset]) -> [PhotoAsset] {
        list.filter { !$0.mightHavePeople && !$0.isFavorite }
    }

    /// Whether "Select All" over `list` has been done, judged against what it is allowed to
    /// take. Judged against the whole list, a section with one person in it never counted
    /// as selected, so its button stayed on "Select All" and could never deselect. When
    /// nothing can be bulk-selected, it means the user picked every item by hand.
    func isBulkSelected(_ list: [PhotoAsset], in category: CleanupCategory) -> Bool {
        let bulk = Self.bulkSelectable(list)
        let target = bulk.isEmpty ? list : bulk
        return !target.isEmpty && target.allSatisfy { isSelected($0.id, in: category) }
    }

    func select(_ list: [PhotoAsset], in category: CleanupCategory) {
        var set = assets[category] ?? []
        for asset in list {
            set.insert(asset.id)
            sizes[asset.id] = asset.bytes
            items[asset.id] = asset
        }
        assets[category] = set
    }

    func deselect(_ list: [PhotoAsset], in category: CleanupCategory) {
        var set = assets[category] ?? []
        for asset in list { set.remove(asset.id) }
        assets[category] = set
    }

    func clear(_ category: CleanupCategory) {
        assets[category] = []
    }

    func clearAll() {
        assets = [:]
        sizes = [:]
        items = [:]
    }

    /// Forget assets that are gone (after a successful delete).
    func remove(ids: Set<String>) {
        for key in assets.keys {
            assets[key]?.subtract(ids)
        }
        for id in ids {
            sizes.removeValue(forKey: id)
            items.removeValue(forKey: id)
        }
    }
}
