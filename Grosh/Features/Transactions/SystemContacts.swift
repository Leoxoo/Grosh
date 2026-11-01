import Contacts

/// Reads the user's Contacts with the Contacts framework. Only the name and phone numbers of each contact are fetched,
/// and fetching runs off the main actor (ADR-0009).
struct SystemContacts: ContactLookup {
    var access: ContactsAccess {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized: .authorized
        case .limited: .limited
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAccess() async -> ContactsAccess {
        _ = try? await CNContactStore().requestAccess(for: .contacts)
        return access
    }

    func search(_ typed: String) async -> [Contact] {
        guard access.showsContacts else { return [] }
        return await ContactsReader.all().filter(nameContaining: typed, name: \.name)
    }

    func contacts(withIdentifiers identifiers: [String]) async -> [Contact] {
        guard access.showsContacts, !identifiers.isEmpty else { return [] }
        return await ContactsReader.contacts(withIdentifiers: identifiers)
    }
}

/// The reads of ``SystemContacts``, which run on the global executor rather than the main actor.
private nonisolated enum ContactsReader {
    /// What a contact is read for: the keys its full name needs, and its phone numbers.
    private static var keys: [CNKeyDescriptor] {
        [CNContactFormatter.descriptorForRequiredKeys(for: .fullName), CNContactPhoneNumbersKey as CNKeyDescriptor]
    }

    /// Every contact the app can see, by name. Under Limited Access that is the ones the user shared.
    @concurrent
    static func all() async -> [Contact] {
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .userDefault
        var found: [CNContact] = []
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in found.append(contact) }
        return found.compactMap(read)
    }

    /// The contacts `identifiers` resolve to; an identifier that doesn't resolve is left out.
    @concurrent
    static func contacts(withIdentifiers identifiers: [String]) async -> [Contact] {
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        let found = (try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []
        return found.compactMap(read)
    }

    /// `nil` for a contact with no name to give a Person.
    private static func read(_ contact: CNContact) -> Contact? {
        guard let name = CNContactFormatter.string(from: contact, style: .fullName), !name.isEmpty else { return nil }
        return Contact(
            identifier: contact.identifier, name: name, phoneNumbers: contact.phoneNumbers.map(\.value.stringValue)
        )
    }
}
