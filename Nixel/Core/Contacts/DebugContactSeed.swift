#if DEBUG
import Foundation
import Contacts

/// Creates a small set of deliberately-messy contacts for testing the duplicate finder.
///
/// Debug builds only — this never ships. It exists because the simulator starts with an
/// empty address book, and the duplicate matcher needs realistic cases to verify against:
/// the same person saved twice under different formatting, a shared phone with different
/// names, and records that must *not* be grouped.
enum DebugContactSeed {

    struct Spec {
        var given: String
        var family: String
        var org: String = ""
        var phones: [String] = []
        var emails: [String] = []
    }

    /// Expected outcome: 3 duplicate groups, and the last three left alone.
    static let fixtures: [Spec] = [
        // Group 1 — same person, different formatting + extra details on one copy
        Spec(given: "Ada", family: "Lovelace", phones: ["+91 98765 43210"], emails: ["ada@analytical.co"]),
        Spec(given: "ada", family: "lovelace", org: "Analytical Engines",
             phones: ["09876543210"], emails: ["ada.lovelace@work.com"]),

        // Group 2 — different spellings, linked by a shared phone number
        Spec(given: "Grace", family: "Hopper", phones: ["+1 (415) 555-0132"]),
        Spec(given: "G.", family: "Hopper", phones: ["4155550132"], emails: ["grace@navy.mil"]),

        // Group 3 — three copies, linked by email then name
        Spec(given: "Alan", family: "Turing", emails: ["alan@bletchley.uk"]),
        Spec(given: "Alan", family: "Turing", phones: ["+44 7700 900123"]),
        Spec(given: "Alan M", family: "Turing", emails: ["alan@bletchley.uk"], ),

        // Must NOT group — distinct people, no shared details
        Spec(given: "Katherine", family: "Johnson", phones: ["+1 202 555 0177"]),
        Spec(given: "Radia", family: "Perlman", emails: ["radia@spanning.net"]),
        Spec(given: "Barbara", family: "Liskov", phones: ["+1 617 555 0144"])
    ]

    static func seed() throws {
        let store = CNContactStore()
        let request = CNSaveRequest()

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
        }

        try store.execute(request)
    }

    /// Removes every contact, so a test run can start clean.
    static func wipe() throws {
        let store = CNContactStore()
        let keys = [CNContactIdentifierKey as CNKeyDescriptor]
        let fetch = CNContactFetchRequest(keysToFetch: keys)
        fetch.unifyResults = false

        let request = CNSaveRequest()
        try store.enumerateContacts(with: fetch) { contact, _ in
            if let mutable = contact.mutableCopy() as? CNMutableContact {
                request.delete(mutable)
            }
        }
        try store.execute(request)
    }
}
#endif
