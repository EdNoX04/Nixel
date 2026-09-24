import Foundation
import Contacts

/// Finds contacts that look like the same person.
///
/// One subtlety that decides whether this feature works at all: `CNContactFetchRequest`
/// defaults `unifyResults` to `true`, which means iOS has *already* merged linked contacts
/// before handing them over. Fetching unified results would hide most real duplicates. We
/// ask for the raw individual records instead.
actor ContactScanner {

    /// Keys to fetch.
    ///
    /// Two traps here, both of which fail *silently* as "no duplicates found":
    ///
    ///  * These constants are Swift `String`s and `CNKeyDescriptor` is an Objective-C
    ///    protocol, so they must be bridged explicitly. An `as?` cast drops every one of
    ///    them and you end up fetching almost nothing.
    ///  * `CNContactNoteKey` requires the `com.apple.developer.contacts.notes` entitlement,
    ///    which Apple grants by application. Asking for it without the entitlement makes
    ///    the whole fetch throw, so notes are deliberately not requested.
    private static let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactMiddleNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactUrlAddressesKey as CNKeyDescriptor,
        CNContactBirthdayKey as CNKeyDescriptor,
        CNContactImageDataAvailableKey as CNKeyDescriptor,
        CNContactThumbnailImageDataKey as CNKeyDescriptor,
        CNContactImageDataKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
    ]

    func fetchAll() throws -> [ContactRecord] {
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: Self.keys)
        request.unifyResults = false          // see the real records, not iOS's merged view
        request.sortOrder = .givenName

        var records: [ContactRecord] = []
        // Deliberately not `try?`: a thrown fetch and an address book with no duplicates
        // look identical to the user otherwise, and that hid two bugs during development.
        try store.enumerateContacts(with: request) { contact, _ in
            records.append(ContactRecord(contact))
        }
        return records
    }

    /// Groups records that appear to be the same person.
    ///
    /// Three independent signals, any of which links two records: an identical normalised
    /// name, a shared phone number, or a shared email. Union-find then merges the chains,
    /// so A–B by phone and B–C by email produce one group of three.
    func duplicateGroups(from records: [ContactRecord]) -> [ContactDuplicateGroup] {
        guard records.count > 1 else { return [] }

        var union = ContactUnionFind(count: records.count)
        // Reasons are attached to a group only once every link is in: a root found
        // mid-way can stop being the root after a later union, taking its reasons with it.
        var links: [(Int, DuplicateReason)] = []

        func link(_ a: Int, _ b: Int, _ reason: DuplicateReason) {
            union.union(a, b)
            links.append((a, reason))
        }

        // Name buckets — only for names that are real, so a pile of "No Name" entries
        // never collapses into one bogus group.
        var byName: [String: [Int]] = [:]
        for (index, record) in records.enumerated() {
            let key = ContactMatching.normaliseName(record.displayName)
            guard !key.isEmpty, record.displayName != "No Name" else { continue }
            byName[key, default: []].append(index)
        }
        // A shared name alone is weak evidence — two different John Smiths share one. So a
        // name only links cards whose details don't contradict each other: if both have
        // phone numbers and none match, or both have emails and none match, they're kept
        // apart. Complementary cards (one with a number, one with an email) still link.
        func conflicting(_ a: ContactRecord, _ b: ContactRecord) -> Bool {
            if !a.phones.isEmpty, !b.phones.isEmpty, Set(a.phones).isDisjoint(with: b.phones) { return true }
            if !a.emails.isEmpty, !b.emails.isEmpty, Set(a.emails).isDisjoint(with: b.emails) { return true }
            return false
        }
        for (_, indices) in byName where indices.count > 1 {
            for i in 0..<indices.count {
                for j in (i + 1)..<indices.count
                where !conflicting(records[indices[i]], records[indices[j]]) {
                    link(indices[i], indices[j], .sameName)
                }
            }
        }

        var byPhone: [String: [Int]] = [:]
        for (index, record) in records.enumerated() {
            for phone in record.phones where phone.count >= 7 {
                byPhone[phone, default: []].append(index)
            }
        }
        for (_, indices) in byPhone where indices.count > 1 {
            for i in 1..<indices.count { link(indices[0], indices[i], .samePhone) }
        }

        var byEmail: [String: [Int]] = [:]
        for (index, record) in records.enumerated() {
            for email in record.emails { byEmail[email, default: []].append(index) }
        }
        for (_, indices) in byEmail where indices.count > 1 {
            for i in 1..<indices.count { link(indices[0], indices[i], .sameEmail) }
        }

        var reasons: [Int: Set<DuplicateReason>] = [:]
        for (index, reason) in links { reasons[union.find(index), default: []].insert(reason) }

        var components: [Int: [Int]] = [:]
        for index in records.indices {
            components[union.find(index), default: []].append(index)
        }

        var groups: [ContactDuplicateGroup] = []
        for (root, indices) in components where indices.count > 1 {
            let members = indices.map { records[$0] }
            let keeper = Self.pickKeeper(from: members)
            let found = reasons[root] ?? []
            let reason: DuplicateReason = found.count > 1 ? .multiple : (found.first ?? .sameName)
            groups.append(ContactDuplicateGroup(
                id: members.map(\.id).sorted().joined(separator: "|"),
                records: members.sorted { $0.id == keeper ? true : ($1.id == keeper ? false : $0.fieldCount > $1.fieldCount) },
                keeperID: keeper,
                reason: reason
            ))
        }

        return groups
            .filter { !Self.alreadyLinked($0) }
            .sorted { $0.records.count > $1.records.count }
    }

    /// Cards iOS already shows as one person (linked across iCloud, Gmail, Exchange…) are
    /// not duplicates to the user — and "merging" them would delete a card on another
    /// account. `unifyResults = false` surfaces them separately, so filter them here.
    private static func alreadyLinked(_ group: ContactDuplicateGroup) -> Bool {
        guard let first = group.records.first else { return false }
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        guard let unified = try? CNContactStore().unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: [first.id]),
            keysToFetch: keys).first else { return false }
        return group.records.dropFirst().allSatisfy {
            unified.isUnifiedWithContact(withIdentifier: $0.id)
        }
    }

    /// Keep whichever record carries the most information — a photo counts, and so does
    /// every extra phone number or address. Merging then folds the rest into it.
    private static func pickKeeper(from records: [ContactRecord]) -> String {
        let best = records.max { a, b in
            if a.fieldCount != b.fieldCount { return a.fieldCount < b.fieldCount }
            if a.hasImage != b.hasImage { return !a.hasImage && b.hasImage }
            return a.displayName.count < b.displayName.count
        }
        return best?.id ?? records[0].id
    }
}

private struct ContactUnionFind {
    private var parent: [Int]
    init(count: Int) { parent = Array(0..<count) }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var current = x
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        if ra != rb { parent[rb] = ra }
    }
}
