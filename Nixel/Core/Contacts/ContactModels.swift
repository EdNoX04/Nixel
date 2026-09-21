import Foundation
import Contacts

/// A contact reduced to the fields we match and display on.
struct ContactRecord: Identifiable, Hashable {
    let id: String                  // CNContact.identifier
    let contact: CNContact
    let displayName: String
    let phones: [String]            // normalised
    let emails: [String]            // lowercased
    let hasImage: Bool
    let fieldCount: Int             // how much information this record carries

    init(_ contact: CNContact) {
        id = contact.identifier
        self.contact = contact

        let formatted = CNContactFormatter.string(from: contact, style: .fullName)
        let fallback = [contact.organizationName, contact.nickname]
            .first { !$0.isEmpty } ?? ""
        displayName = (formatted?.trimmingCharacters(in: .whitespaces)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? (fallback.isEmpty ? "No Name" : fallback)

        phones = contact.phoneNumbers
            .map { ContactMatching.normalisePhone($0.value.stringValue) }
            .filter { !$0.isEmpty }
        emails = contact.emailAddresses
            .map { ($0.value as String).lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        hasImage = contact.imageDataAvailable
        fieldCount =
            contact.phoneNumbers.count +
            contact.emailAddresses.count +
            contact.postalAddresses.count +
            contact.urlAddresses.count +
            (contact.organizationName.isEmpty ? 0 : 1) +
            (contact.birthday == nil ? 0 : 1) +
            (contact.jobTitle.isEmpty ? 0 : 1) +
            (contact.imageDataAvailable ? 1 : 0)
    }

    static func == (a: ContactRecord, b: ContactRecord) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Why a set of contacts was flagged as duplicates — shown to the user so the call is
/// never a black box.
enum DuplicateReason: String {
    case sameName = "Same name"
    case samePhone = "Shared phone number"
    case sameEmail = "Shared email"
    case multiple = "Name and details match"

    var icon: String {
        switch self {
        case .sameName:  return "person.text.rectangle"
        case .samePhone: return "phone"
        case .sameEmail: return "envelope"
        case .multiple:  return "checkmark.seal"
        }
    }
}

struct ContactDuplicateGroup: Identifiable, Hashable {
    let id: String
    var records: [ContactRecord]
    /// The record we suggest keeping — the most complete one.
    var keeperID: String
    var reason: DuplicateReason

    var keeper: ContactRecord? { records.first { $0.id == keeperID } }
    var others: [ContactRecord] { records.filter { $0.id != keeperID } }

    static func == (a: ContactDuplicateGroup, b: ContactDuplicateGroup) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum ContactMatching {

    /// Reduces a phone number to something comparable.
    ///
    /// Country codes and formatting vary between the same number saved twice, so we keep
    /// the last 10 digits — long enough to be specific, short enough that "+91 98765 43210"
    /// and "09876543210" land on the same key.
    static func normalisePhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard digits.count >= 7 else { return digits }
        return String(digits.suffix(10))
    }

    /// Case- and punctuation-insensitive name key.
    static func normaliseName(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .sorted()          // "Ada Lovelace" and "Lovelace, Ada" match
            .joined(separator: " ")
    }
}
