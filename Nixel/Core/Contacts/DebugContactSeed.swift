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

    /// Ground truth: sixteen duplicate groups (nineteen extras) and twenty-seven people who
    /// must not be grouped with anyone.
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
        Spec(given: "Grace", family: "Kim", phones: ["+1 503 555 0125"]),

        // ---- second batch ----

        // 7 — accent typed on one copy only
        Spec(given: "Zoë", family: "Laurent", phones: ["+1 617 555 0114"]),
        Spec(given: "Zoe", family: "Laurent", emails: ["zoe.laurent@example.com"]),

        // 8 — surname and given name swapped
        Spec(given: "Kwame", family: "Asante", phones: ["+1 470 555 0126"]),
        Spec(given: "Asante", family: "Kwame", emails: ["kwame@example.com"]),

        // 9 — work card and a quick-add, linked by number
        Spec(given: "Elena", family: "Rossi", org: "Brightline Studio",
             phones: ["+1 305 555 0152"], emails: ["elena.rossi@example.org"]),
        Spec(given: "Elena", family: "R.", phones: ["305-555-0152"]),

        // 10 — three copies, chained by name then email
        Spec(given: "Marcus", family: "Webb", phones: ["+1 213 555 0139"]),
        Spec(given: "Marcus", family: "Webb", emails: ["marcus.webb@example.net"]),
        Spec(given: "Marc", family: "Webb", emails: ["marcus.webb@example.net"]),

        // 11 — a business saved with no name, and the person behind it
        Spec(given: "Jake", family: "Turner", org: "Turner Plumbing", phones: ["+1 480 555 0171"]),
        Spec(given: "", family: "", org: "Turner Plumbing", phones: ["480.555.0171"]),

        // 12 — first name only, same UK number in two formats
        Spec(given: "Anika", family: "Sharma", phones: ["+44 7700 900456"]),
        Spec(given: "Anika", family: "", phones: ["07700 900456"]),

        // 13 — email capitalised differently
        Spec(given: "Ben", family: "Carter", emails: ["Ben.Carter@Example.com"]),
        Spec(given: "Benjamin", family: "Carter", emails: ["ben.carter@example.com"]),

        // 14 — title typed into the name field
        Spec(given: "Fatima", family: "Noor", org: "Lakeside Clinic", phones: ["+1 773 555 0164"]),
        Spec(given: "Dr Fatima", family: "Noor", phones: ["(773) 555 0164"]),

        // 15 — saved as a relationship, and again by name
        Spec(given: "Mum", family: "", phones: ["+1 919 555 0107"]),
        Spec(given: "Linda", family: "Hart", phones: ["919-555-0107"], emails: ["linda.hart@example.net"]),

        // 16 — three copies linked by name, number and email
        Spec(given: "Kenji", family: "Watanabe", phones: ["+1 206 555 0158"]),
        Spec(given: "Kenji", family: "W", phones: ["206 555 0158"], emails: ["kenji@example.org"]),
        Spec(given: "Kenji", family: "Watanabe", emails: ["kenji@example.org"]),

        // Must NOT be grouped — including near-misses on names already used above
        Spec(given: "Priya", family: "Nair", phones: ["+1 510 555 0193"]),
        Spec(given: "Daniel", family: "Okoro", emails: ["daniel.okoro@example.net"]),
        Spec(given: "Wei", family: "Chen", phones: ["+1 347 555 0129"]),
        Spec(given: "Sam", family: "Rivera", emails: ["sam.rivera@example.com"]),
        Spec(given: "Isla", family: "Fraser", phones: ["+44 7700 900789"]),
        Spec(given: "Noah", family: "Fischer", phones: ["+1 612 555 0135"]),
        Spec(given: "Leila", family: "Karimi", emails: ["leila@example.org"]),
        Spec(given: "Mateo", family: "Silva", phones: ["+1 702 555 0144"]),
        Spec(given: "Harper", family: "Quinn", emails: ["harper.quinn@example.net"]),
        Spec(given: "Yusuf", family: "Demir", phones: ["+1 832 555 0117"]),
        Spec(given: "Olivia", family: "Grant", org: "Grant & Co", emails: ["olivia@example.com"]),
        Spec(given: "Ethan", family: "Brooks", phones: ["+1 614 555 0182"]),
        Spec(given: "Amara", family: "Nwosu", emails: ["amara.nwosu@example.org"]),
        Spec(given: "Felix", family: "Wagner", phones: ["+44 7700 900321"]),
        Spec(given: "Inês", family: "Costa", emails: ["ines.costa@example.net"]),
        Spec(given: "", family: "", org: "Bright Smile Dental", phones: ["+1 408 555 0156"]),
        Spec(given: "Ruby", family: "Clarke", phones: ["+1 971 555 0103"]),
        Spec(given: "Leo", family: "Martins", emails: ["leo.martins@example.com"]),
        Spec(given: "Tara", family: "Singh", phones: ["+1 267 555 0161"]),
        Spec(given: "Victor", family: "Hale", emails: ["victor.hale@example.org"])
    ]

    private static var manifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("demo-contacts.json")
    }

    static var seededCount: Int { loadManifest().count }

    // MARK: Seed

    struct SeedResult {
        var added = 0
        var removed = 0
    }

    /// Brings the demo contacts to exactly one copy of each fixture.
    ///
    /// Matching is by content, not by position, so it copes with every state a test phone
    /// ends up in: nothing seeded yet, a list that has since grown, Add tapped twice, or
    /// demo contacts already merged in the app. Surplus or edited copies are removed —
    /// only ever from this seeder's own manifest — and missing fixtures are added.
    @discardableResult
    static func seed() throws -> SeedResult {
        let store = CNContactStore()
        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey, CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactOrganizationNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey
        ].map { $0 as CNKeyDescriptor }

        let manifest = loadManifest()
        let existing = manifest.isEmpty ? [] : ((try? store.unifiedContacts(
            matching: CNContact.predicateForContacts(withIdentifiers: manifest),
            keysToFetch: keys)) ?? []).filter { manifest.contains($0.identifier) }

        var unclaimed: [String: [CNContact]] = [:]
        for contact in existing { unclaimed[signature(of: contact), default: []].append(contact) }

        var kept: [String] = []
        var missing: [Spec] = []
        for spec in fixtures {
            let key = signature(of: spec)
            if let match = unclaimed[key]?.first {
                unclaimed[key]?.removeFirst()
                kept.append(match.identifier)
            } else {
                missing.append(spec)
            }
        }
        let surplus = unclaimed.values.flatMap { $0 }
        guard !missing.isEmpty || !surplus.isEmpty else {
            saveManifest(kept)
            return SeedResult()
        }

        let request = CNSaveRequest()
        for contact in surplus {
            if let mutable = contact.mutableCopy() as? CNMutableContact { request.delete(mutable) }
        }
        var created: [CNMutableContact] = []
        for spec in missing {
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
        saveManifest(kept + created.map(\.identifier))
        return SeedResult(added: created.count, removed: surplus.count)
    }

    private static func signature(given: String, family: String, org: String,
                                  phones: [String], emails: [String]) -> String {
        [given, family, org,
         phones.map(ContactMatching.normalisePhone).joined(separator: ","),
         emails.map { $0.lowercased() }.joined(separator: ",")].joined(separator: "|")
    }

    private static func signature(of spec: Spec) -> String {
        signature(given: spec.given, family: spec.family, org: spec.org,
                  phones: spec.phones, emails: spec.emails)
    }

    private static func signature(of contact: CNContact) -> String {
        signature(given: contact.givenName, family: contact.familyName,
                  org: contact.organizationName,
                  phones: contact.phoneNumbers.map { $0.value.stringValue },
                  emails: contact.emailAddresses.map { $0.value as String })
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
