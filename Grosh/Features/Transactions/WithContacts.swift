import Contacts
import SwiftData
import SwiftUI
#if os(iOS)
import ContactsUI
#endif

/// What the With menu knows of the user's Contacts: whether it may read them and the contacts that match what was typed.
/// Contacts permission is asked for the first time the menu opens, never at launch (ADR-0009).
@Observable
final class ContactsInWith {
    /// What the user has allowed. The Contacts section is listed only while it ``ContactsAccess/showsContacts``.
    private(set) var access: ContactsAccess
    /// The contacts matching what was typed, by name.
    private(set) var results: [Contact] = []

    private let lookup: any ContactLookup

    init(lookup: any ContactLookup = SystemContacts()) {
        self.lookup = lookup
        access = lookup.access
    }

    /// Posted when the user's Contacts change.
    static var changed: NotificationCenter.Publisher {
        NotificationCenter.default.publisher(for: .CNContactStoreDidChange)
    }

    /// Done when the menu opens: asks for access if the user hasn't answered, brings the linked people up to date with
    /// their contacts, and lists every contact.
    func open(in context: ModelContext) async {
        access = await lookup.accessForMenu()
        await refreshPeople(in: context)
        await search("")
    }

    /// Brings the people linked to a contact up to date with it. Nothing changes for a contact that can't be read.
    func refreshPeople(in context: ModelContext) async {
        access = lookup.access
        guard access.showsContacts else { return }
        try? await Person.refreshFromContacts(using: lookup, in: context)
    }

    /// Lists the contacts matching `typed`, a moment after the last keystroke. Reads off the main actor, so typing stays
    /// smooth. Cancelled by the next keystroke.
    func search(_ typed: String) async {
        guard access.showsContacts else {
            results = []
            return
        }
        if !typed.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled { return }
        }
        let found = await lookup.search(typed)
        if !Task.isCancelled {
            results = found
        }
    }
}

/// The With menu's Contacts section: the contacts matching what was typed. Picking one calls `pick` with the contact and
/// the number to keep; a contact with several numbers first asks which. Under Limited Access, `ContactAccessButton` lets
/// the user share a contact that matches what was typed. Nothing is listed while access is denied (ADR-0009).
struct WithContactsSection: View {
    let contacts: ContactsInWith
    let typed: String
    let pick: (Contact, String?) -> Void

    @State private var choosingNumberFor: Contact?

    var body: some View {
        let showsAccessButton = contacts.access.offersToShareMore && !typed.isEmpty
        if contacts.access.showsContacts, showsAccessButton || !contacts.results.isEmpty {
            Section("Contacts") {
                ForEach(contacts.results) { contact in
                    Button {
                        if contact.needsPhoneChoice {
                            choosingNumberFor = contact
                        } else {
                            pick(contact, nil)
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(contact.name)
                            if let phone = contact.phoneNumbers.first {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .foregroundStyle(.primary)
                }
                #if os(iOS)
                if showsAccessButton {
                    ContactAccessButton(
                        queryString: typed, ignoredPhoneNumbers: Set(contacts.results.flatMap(\.phoneNumbers))
                    ) { _ in
                        Task { await contacts.search(typed) }
                    }
                }
                #endif
            }
            .confirmationDialog(
                "Which number?",
                isPresented: Binding(get: { choosingNumberFor != nil }, set: { if !$0 { choosingNumberFor = nil } }),
                presenting: choosingNumberFor
            ) { contact in
                ForEach(contact.phoneNumbers, id: \.self) { number in
                    Button(number) { pick(contact, number) }
                }
            } message: { contact in
                Text("\(contact.name) has several numbers.")
            }
        }
    }
}
