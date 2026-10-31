import Foundation

/// An entry in the user's Contacts as far as Grosh reads it: the identifier that links a Person to it, the name and the
/// phone numbers. Nothing else of a contact is ever read or copied (ADR-0009).
nonisolated struct Contact: Hashable, Sendable, Identifiable {
    /// What a Person's `contactIdentifier` holds.
    let identifier: String
    let name: String
    /// Every number the contact has, each once, in the order the contact lists them.
    let phoneNumbers: [String]

    var id: String { identifier }

    init(identifier: String, name: String, phoneNumbers: [String] = []) {
        self.identifier = identifier
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var numbers: [String] = []
        for number in phoneNumbers.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        where !number.isEmpty && !numbers.contains(number) {
            numbers.append(number)
        }
        self.phoneNumbers = numbers
    }
}

nonisolated extension Contact {
    /// Whether picking the contact has to ask which number to keep: it has several.
    var needsPhoneChoice: Bool {
        phoneNumbers.count > 1
    }

    /// The number a Person keeps from this contact: `preferred` while the contact still has it, otherwise the contact's
    /// first number, or `nil` when it has none. Picking a contact passes the number the user chose; refreshing passes
    /// the number the Person has, so a Person keeps their number for as long as the contact does.
    func phone(preferring preferred: String?) -> String? {
        if let preferred, phoneNumbers.contains(preferred) { return preferred }
        return phoneNumbers.first
    }
}

/// What the user has allowed Grosh to read of their Contacts.
nonisolated enum ContactsAccess: Hashable, Sendable {
    /// The user hasn't been asked yet.
    case notDetermined
    /// The user said no, or Contacts is restricted on the device.
    case denied
    /// The user shared only some contacts. More are shared one at a time, with `ContactAccessButton`.
    case limited
    /// The user shared them all.
    case authorized

    /// Whether the With menu lists a Contacts section: with access denied, or not asked for yet, it is Previous and
    /// typing only.
    var showsContacts: Bool {
        self == .authorized || self == .limited
    }

    /// Whether the With menu offers to share more contacts.
    var offersToShareMore: Bool {
        self == .limited
    }
}

/// Where Grosh reads the user's Contacts: the Contacts framework in the app, a stand-in in tests. A Person links to a
/// contact by its identifier alone (ADR-0009). It is also how a later feature resolves that identifier to the contact's
/// current phone number (``contact(withIdentifier:)``).
protocol ContactLookup {
    /// What the user has allowed right now, without asking.
    var access: ContactsAccess { get }
    /// Asks the user to allow reading their Contacts, unless they already answered. Returns what they allowed.
    func requestAccess() async -> ContactsAccess
    /// The contacts whose names contain `typed`, or all of them while nothing is typed, by name. Empty while access
    /// isn't ``ContactsAccess/showsContacts``. Reads off the main actor.
    func search(_ typed: String) async -> [Contact]
    /// The contacts that `identifiers` resolve to now. An identifier that doesn't resolve, because the contact was
    /// deleted, isn't shared under Limited Access or is stale, is left out, and so is every one while access isn't
    /// ``ContactsAccess/showsContacts``. Never asks the user for access.
    func contacts(withIdentifiers identifiers: [String]) async -> [Contact]
}

extension ContactLookup {
    /// The contact `identifier` resolves to now, or `nil` when it doesn't.
    func contact(withIdentifier identifier: String) async -> Contact? {
        await contacts(withIdentifiers: [identifier]).first
    }

    /// What the With menu does when it opens: asks for access only while the user hasn't answered, so Contacts is never
    /// touched before the menu needs it. Returns what they allowed.
    func accessForMenu() async -> ContactsAccess {
        access == .notDetermined ? await requestAccess() : access
    }
}
