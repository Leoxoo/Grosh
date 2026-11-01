import Foundation
import SwiftData

extension Person {
    /// Chooses the Person for a contact picked in the With menu, and links them to it: the contact's identifier, name and
    /// phone are stored on the Person as snapshots (ADR-0009). The Person is the one already linked to the contact, or
    /// else the one who has the contact's name, ignoring case, so picking a contact never makes a second Person of the
    /// same name; failing both, a new one. Like typing the name, it brings back a hidden Person and makes them the most
    /// recent. Saves. Throws ``PersonRuleError/missingName`` for a contact with no name.
    ///
    /// The phone is `phone` when the contact has it (the number the user chose when it has several), else the Person's
    /// own number when the contact has it, otherwise the contact's first number. A contact with no number leaves the
    /// Person's own.
    @discardableResult
    static func add(_ contact: Contact, phone: String? = nil, in context: ModelContext) throws -> Person {
        let everyone = try context.fetch(FetchDescriptor<Person>())
        let linked = everyone.first { $0.contactIdentifier == contact.identifier }
        let person = try add(named: linked?.name ?? contact.name, in: context)
        person.contactIdentifier = contact.identifier
        person.take(contact, preferringPhone: phone ?? person.phone, among: everyone)
        try context.save()
        return person
    }

    /// Brings every Person linked to a contact up to date with it: the name and the phone, as the contact has them now.
    /// A Person whose identifier doesn't resolve, because the contact was deleted, isn't shared or is stale, keeps what
    /// is stored, and so does everyone while access to Contacts is off. Does nothing, and asks nothing of `lookup`, when
    /// no Person is linked. Saves when something changed.
    ///
    /// Done when the With menu opens and when iOS reports a change to Contacts.
    @MainActor
    static func refreshFromContacts(using lookup: some ContactLookup, in context: ModelContext) async throws {
        let everyone = try context.fetch(FetchDescriptor<Person>())
        let linked = everyone.filter { $0.contactIdentifier != nil }
        guard !linked.isEmpty else { return }
        let found = await lookup.contacts(withIdentifiers: linked.compactMap(\.contactIdentifier))
        let contacts = Dictionary(found.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        for person in linked {
            guard let identifier = person.contactIdentifier, let contact = contacts[identifier] else { continue }
            person.take(contact, preferringPhone: person.phone, among: everyone)
        }
        if context.hasChanges {
            try context.save()
        }
    }

    /// Renames the Person and keeps ``Transaction/withName`` in step on every transaction they are in, Recently Deleted
    /// ones included (ADR-0009). Does nothing when the name is the same. Doesn't save.
    func rename(to newName: String) {
        guard name != newName else { return }
        name = newName
        for transaction in transactions ?? [] {
            transaction.refreshWithName()
        }
    }

    /// Takes the contact's name and phone. The name is left alone when another Person has it already, since two people
    /// never share a name (ADR-0009); a name in a contact that is empty is never taken. The phone is left alone when the
    /// contact has none. Doesn't save.
    private func take(_ contact: Contact, preferringPhone preferred: String?, among everyone: [Person]) {
        let key = Person.key(contact.name)
        if !key.isEmpty, !everyone.contains(where: { $0 !== self && Person.key($0.name) == key }) {
            rename(to: contact.name)
        }
        if let phone = contact.phone(preferring: preferred), phone != self.phone {
            self.phone = phone
        }
    }
}
