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

    /// Folds `group`'s duplicates into its keeper and removes them.
    /// Returns the ids that were deleted.
    @discardableResult
    static func merge(_ group: ContactDuplicateGroup) throws -> Set<String> {
        guard let keeper = group.keeper, !group.others.isEmpty else { return [] }

        let merged = keeper.contact.mutableCopy() as! CNMutableContact
        var seenPhones = Set(keeper.phones)
        var seenEmails = Set(keeper.emails)
        var seenAddresses = Set(keeper.contact.postalAddresses.map { describe($0.value) })
        var seenURLs = Set(keeper.contact.urlAddresses.map { ($0.value as String).lowercased() })

        for other in group.others {
            let contact = other.contact

            for phone in contact.phoneNumbers {
                let key = ContactMatching.normalisePhone(phone.value.stringValue)
                guard !key.isEmpty, !seenPhones.contains(key) else { continue }
                seenPhones.insert(key)
                merged.phoneNumbers.append(phone)
            }

            for email in contact.emailAddresses {
                let key = (email.value as String).lowercased()
                guard !key.isEmpty, !seenEmails.contains(key) else { continue }
                seenEmails.insert(key)
                merged.emailAddresses.append(email)
            }

            for address in contact.postalAddresses {
                let key = describe(address.value)
                guard !seenAddresses.contains(key) else { continue }
                seenAddresses.insert(key)
                merged.postalAddresses.append(address)
            }

            for url in contact.urlAddresses {
                let key = (url.value as String).lowercased()
                guard !seenURLs.contains(key) else { continue }
                seenURLs.insert(key)
                merged.urlAddresses.append(url)
            }

            // Scalar fields: only fill gaps, never overwrite what the keeper already has.
            if merged.organizationName.isEmpty { merged.organizationName = contact.organizationName }
            if merged.jobTitle.isEmpty { merged.jobTitle = contact.jobTitle }
            if merged.nickname.isEmpty { merged.nickname = contact.nickname }
            if merged.birthday == nil { merged.birthday = contact.birthday }
            if merged.givenName.isEmpty { merged.givenName = contact.givenName }
            if merged.familyName.isEmpty { merged.familyName = contact.familyName }
            if merged.imageData == nil, contact.imageDataAvailable {
                merged.imageData = contact.imageData
            }
        }

        let request = CNSaveRequest()
        request.update(merged)
        for other in group.others {
            guard let mutable = other.contact.mutableCopy() as? CNMutableContact else { continue }
            request.delete(mutable)
        }

        do {
            try CNContactStore().execute(request)
        } catch {
            throw MergeError.saveFailed(error.localizedDescription)
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
            throw MergeError.saveFailed(error.localizedDescription)
        }
        return Set(records.map(\.id))
    }

    private static func describe(_ address: CNPostalAddress) -> String {
        [address.street, address.city, address.postalCode, address.country]
            .joined(separator: "|")
            .lowercased()
    }
}
