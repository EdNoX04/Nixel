#if DEBUG
import Foundation
import Contacts

/// Creates a set of stand-in contacts for demos and device tests, and removes them again.
///
/// Debug builds only. Two rules shape it, both learned the hard way:
///
///  * **It only ever deletes what it created.** An earlier version had a "wipe" that
///    enumerated the whole address book and deleted everything it found. In the Simulator
///    that was harmless; on a real phone with full contacts access it was one tap away from
///    deleting someone's entire address book. Every identifier this creates is written to a
///    manifest, and removal deletes exactly those.
///  * **Nothing here can collide with a real person.** Names are invented, phone numbers
///    sit in ranges reserved for fiction (NANP 555-01xx, Ofcom 07700 900xxx), and email
///    addresses use the RFC 2606 reserved domains.
///
/// For a private demo, grant Nixel *limited* contacts access with nobody selected, then
/// seed: iOS lets an app see the contacts it created itself, so these are all it can read.
enum DebugContactSeed {

    struct Spec {
        var given: String
        var family: String
        var org: String = ""
        var phones: [String] = []
        var emails: [String] = []
    }

    /// Ground truth: six duplicate groups (seven extras) and seven people who must not be
    /// grouped with anyone.
    static let fixtures: [Spec] = [
        // 1 — same person, same number, name typed differently
        Spec(given: "Priya", family: "Raman", phones: ["+1 202 555 0147"], emails: ["priya@example.com"]),
        Spec(given: "priya", family: "raman", phones: ["(202) 555-0147"]),

        // 2 — different names, linked only by a shared number
        Spec(given: "Arjun", family: "Mehta", phones: ["+44 7700 900123"]),
        Spec(given: "A.", family: "Mehta", phones: ["07700900123"], emails: ["arjun.m@example.com"]),

        // 3 — three copies, chained by email and by name
        Spec(given: "Sofia", family: "Alvarez", emails: ["sofia@example.org"]),
        Spec(given: "Sofia", family: "Alvarez", phones: ["+1 312 555 0176"]),
        Spec(given: "Sofia M", family: "Alvarez", emails: ["sofia@example.org"]),

        // 4 — nickname, linked by email; one copy carries the company
        Spec(given: "Daniel", family: "Okafor", org: "Northwind Traders",
             emails: ["daniel.okafor@example.com"]),
        Spec(given: "Dan", family: "Okafor", emails: ["daniel.okafor@example.com"]),

        // 5 — spacing differs in the name, number formatted differently
        Spec(given: "Mei Lin", family: "Chen", phones: ["+1 415 555 0133"]),
        Spec(given: "Meilin", family: "Chen", phones: ["(415) 555-0133"]),

        // 6 — same name, complementary details
        Spec(given: "Lucas", family: "Moreau", phones: ["+1 646 555 0188"]),
        Spec(given: "Lucas", family: "Moreau", emails: ["lucas@example.net"]),

        // Must NOT be grouped — distinct people, nothing shared
        Spec(given: "Hannah", family: "Becker", phones: ["+1 206 555 0110"]),
        Spec(given: "Ravi", family: "Kumar", emails: ["ravi@example.com"]),
        Spec(given: "Aisha", family: "Bello", phones: ["+1 404 555 0191"]),
        Spec(given: "Tom", family: "Whitfield", emails: ["tom@example.org"]),
        Spec(given: "Nina", family: "Petrova", phones: ["+1 718 555 0162"]),
        Spec(given: "Omar", family: "Haddad", emails: ["omar@example.net"]),
        Spec(given: "Grace", family: "Kim", phones: ["+1 503 555 0125"])
    ]

    private static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-contacts.json")
    }

    static var seededCount: Int { loadManifest().count }

    // MARK: Seed

    @discardableResult
    static func seed() throws -> Int {
        let store = CNContactStore()
        let request = CNSaveRequest()
        var created: [CNMutableContact] = []

        for spec in fixtures {
            let contact = CNMutableContact()
            contact.givenName = spec.given
            contact.familyName = spec.family
            contact.organizationName = spec.org
            contact.phoneNumbers = spec.phones.map {
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: $0))
            }
            contact.emailAddresses = spec.emails.map {
                CNLabeledValue(label: CNLabelHome, value: $0 as NSString)
            }
            request.add(contact, toContainerWithIdentifier: nil)
            created.append(contact)
        }

        try store.execute(request)

        // Identifiers are assigned on save.
        let ids = created.map(\.identifier)
        saveManifest(loadManifest() + ids)
        return ids.count
    }

    // MARK: Remove

    /// Deletes only the contacts this seeder created. Never enumerates the address book.
    @discardableResult
    static func removeSeeded() throws -> Int {
        let identifiers = loadManifest()
        guard !identifiers.isEmpty else { return 0 }

        let store = CNContactStore()
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        let found = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []

        let request = CNSaveRequest()
        var removed = 0
        for contact in found {
            guard identifiers.contains(contact.identifier),
                  let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
            request.delete(mutable)
            removed += 1
        }
        if removed > 0 { try store.execute(request) }
        saveManifest([])
        return removed
    }

    // MARK: Manifest

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
#endif
