import Testing
@testable import Grosh

/// Stands in for the user's Contacts: holds the contacts a test gives it (its ``book``), answers like the real lookup
/// (nothing is readable unless access is allowed), and records when it is asked for access instead of asking the user. A
/// test makes a contact vanish, as when it is deleted or not shared, by taking it out of ``book``.
@MainActor
final class RecordingContactLookup: ContactLookup {
    enum Call: Equatable {
        case requestAccess
        case search(String)
        case contacts([String])
    }

    var book: [Contact]
    private(set) var access: ContactsAccess
    /// What the user answers when asked for access.
    private let answer: ContactsAccess
    private(set) var calls: [Call] = []

    /// A user who has been asked already, or who will `answer` when asked.
    init(_ contacts: [Contact] = [], access: ContactsAccess = .authorized, answer: ContactsAccess = .authorized) {
        self.book = contacts
        self.access = access
        self.answer = answer
    }

    func requestAccess() async -> ContactsAccess {
        calls.append(.requestAccess)
        if access == .notDetermined {
            access = answer
        }
        return access
    }

    func search(_ typed: String) async -> [Contact] {
        calls.append(.search(typed))
        return access.showsContacts ? book.filter(nameContaining: typed, name: \.name) : []
    }

    func contacts(withIdentifiers identifiers: [String]) async -> [Contact] {
        calls.append(.contacts(identifiers))
        return access.showsContacts ? book.filter { identifiers.contains($0.identifier) } : []
    }

    /// Changes the user's mind in Settings.
    func allow(_ access: ContactsAccess) {
        self.access = access
    }
}
