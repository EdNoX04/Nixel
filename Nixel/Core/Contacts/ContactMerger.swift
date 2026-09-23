import Foundation
import Contacts

/// Merges and deletes duplicate contacts.
///
/// The Contacts framework has no merge API — `CNSaveRequest` only offers add, update and
/// delete. So a merge is performed by hand: fold every field from the duplicates into the
/// keeper, save that, then delete the now-redundant records. Both halves go in a single
/// `CNSaveRequest` so the operation is atomic; a partial merge that deleted the duplicates
/// without saving the union would lose data permanently.
enum ContactMerger {

    enum MergeError: LocalizedError {
        case saveFailed(String)
        var errorDescription: String? {
            switch self {
            case .saveFailed(let message): return message
            }
        }
    }

    /// Every field Nixel can write back, read fresh at merge time so nothing the scan didn't
    /// look at is dropped. Notes are the one exception: reading them needs an entitlement
    /// Apple grants case by case, so a note on a removed card can't be carried over — the
    /// confirmation dialog says so.
    private static let mergeKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey, CNContactNamePrefixKey, CNContactGivenNameKey,
        CNContactMiddleNameKey, CNContactFamilyNameKey, CNContactNameSuffixKey,
        CNContactNicknameKey, CNContactPhoneticGivenNameKey, CNContactPhoneticMiddleNameKey,
        CNContactPhoneticFamilyNameKey, CNContactOrganizationNameKey, CNContactDepartmentNameKey,
        CNContactJobTitleKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey,
        CNContactPostalAddressesKey, CNContactUrlAddressesKey, CNContactSocialProfilesKey,
        CNContactInstantMessageAddressesKey, CNContactRelationsKey, CNContactDatesKey,
        CNContactBirthdayKey, CNContactNonGregorianBirthdayKey, CNContactImageDataKey,
        CNContactImageDataAvailableKey
    ].map { $0 as CNKeyDescriptor }

    /// Folds `group`'s duplicates into its keeper and removes them.
    /// Returns the ids that were deleted.
    @discardableResult
    static func merge(_ group: ContactDuplicateGroup) throws -> Set<String> {
        guard let keeperRecord = group.keeper, !group.others.isEmpty else { return [] }

        // Re-read every card: the scan may be minutes old, and a card edited since then
        // must not be overwritten with the stale copy.
        let store = CNContactStore()
        let ids = [keeperRecord.id] + group.others.map(\.id)
        let request = CNContactFetchRequest(keysToFetch: mergeKeys)
        request.predicate = CNContact.predicateForContacts(withIdentifiers: ids)
        request.unifyResults = false
        var fresh: [String: CNContact] = [:]
        try store.enumerateContacts(with: request) { contact, _ in fresh[contact.identifier] = contact }
        guard let keeper = fresh[keeperRecord.id],
              group.others.allSatisfy({ fresh[$0.id] != nil }) else {
            throw MergeError.saveFailed("These contacts changed since the scan. Pull to rescan and try again.")
        }
        let others = group.others.compactMap { fresh[$0.id] }

        let merged = keeper.mutableCopy() as! CNMutableContact
        func appendNew<T>(_ values: [CNLabeledValue<T>], to existing: inout [CNLabeledValue<T>],
                          key: (T) -> String) {
            var seen = Set(existing.map { key($0.value) })
            for value in values where !key(value.value).isEmpty && seen.insert(key(value.value)).inserted {
                existing.append(value)
            }
        }

        for contact in others {
            appendNew(contact.phoneNumbers, to: &merged.phoneNumbers) {
                ContactMatching.normalisePhone($0.stringValue)
            }
            appendNew(contact.emailAddresses, to: &merged.emailAddresses) {
                ($0 as String).lowercased().trimmingCharacters(in: .whitespaces)
            }
            appendNew(contact.postalAddresses, to: &merged.postalAddresses) { describe($0) }
            appendNew(contact.urlAddresses, to: &merged.urlAddresses) { ($0 as String).lowercased() }
            appendNew(contact.socialProfiles, to: &merged.socialProfiles) {
                "\($0.service)|\($0.username)|\($0.urlString)".lowercased()
            }
            appendNew(contact.instantMessageAddresses, to: &merged.instantMessageAddresses) {
                "\($0.service)|\($0.username)".lowercased()
            }
            appendNew(contact.contactRelations, to: &merged.contactRelations) { $0.name.lowercased() }
            appendNew(contact.dates, to: &merged.dates) { "\($0.year)-\($0.month)-\($0.day)" }

            // Names are completed rather than just gap-filled: "A. Mehta" merged with
            // "Arjun Mehta" should come out as Arjun.
            merged.givenName = ContactMatching.fuller(merged.givenName, contact.givenName)
            merged.familyName = ContactMatching.fuller(merged.familyName, contact.familyName)

            // Everything else only fills gaps — never overwrites what the keeper has.
            func fill(_ path: ReferenceWritableKeyPath<CNMutableContact, String>, _ value: String) {
                if merged[keyPath: path].isEmpty { merged[keyPath: path] = value }
            }
            fill(\.namePrefix, contact.namePrefix)
            fill(\.middleName, contact.middleName)
            fill(\.nameSuffix, contact.nameSuffix)
            fill(\.nickname, contact.nickname)
            fill(\.phoneticGivenName, contact.phoneticGivenName)
            fill(\.phoneticMiddleName, contact.phoneticMiddleName)
            fill(\.phoneticFamilyName, contact.phoneticFamilyName)
            fill(\.organizationName, contact.organizationName)
            fill(\.departmentName, contact.departmentName)
            fill(\.jobTitle, contact.jobTitle)
            if merged.birthday == nil { merged.birthday = contact.birthday }
            if merged.nonGregorianBirthday == nil { merged.nonGregorianBirthday = contact.nonGregorianBirthday }
            if merged.imageData == nil, contact.imageDataAvailable { merged.imageData = contact.imageData }
        }

        // One request, so the union is saved and the duplicates removed together or not
        // at all — a partial merge that deleted without saving would lose data for good.
        let save = CNSaveRequest()
        save.update(merged)
        for contact in others {
            guard let mutable = contact.mutableCopy() as? CNMutableContact else { continue }
            save.delete(mutable)
        }
        do {
            try store.execute(save)
        } catch {
            throw MergeError.saveFailed("Contacts couldn't be saved. Nothing was changed.")
        }
        return Set(group.others.map(\.id))
    }

    /// Deletes specific contacts outright, without merging anything into a keeper.
    @discardableResult
    static func delete(_ records: [ContactRecord]) throws -> Set<String> {
        guard !records.isEmpty else { return [] }
        let request = CNSaveRequest()
        for record in records {
            guard let mutable = record.contact.mutableCopy() as? CNMutableContact else { continue }
            request.delete(mutable)
        }
        do {
            try CNContactStore().execute(request)
        } catch {
            throw MergeError.saveFailed("Contacts couldn't be deleted. Nothing was changed.")
        }
        return Set(records.map(\.id))
    }

    private static func describe(_ address: CNPostalAddress) -> String {
        [address.street, address.city, address.postalCode, address.country]
            .joined(separator: "|")
            .lowercased()
    }
}
