import Foundation
import SwiftData

/// How a Text them message reaches the user's Messages.
enum TextDelivery: Equatable {
    /// Open the Messages compose sheet to `phone` with `body` filled in. The user taps Send; nothing is sent without it.
    case compose(phone: String, body: String)
    /// Texting isn't available here (the simulator, an iPad without Messages) or the Person has no number: the user can
    /// copy or share `body` instead.
    case copyOrShare(body: String)
}

/// A text message to a Person about what is owed, the user sends from the Messages compose sheet with a tap: the Text
/// button on a Person's row in Debts & Loans, and the "Text them" action on a reminder notification (ADR-0009,
/// ADR-0010). It holds what the message is built from; ``body`` words it, ``phone(using:)`` picks the number and
/// ``delivery(canSendText:using:)`` decides between the compose sheet and copy or share.
struct TextReminder: Identifiable, Equatable {
    let personName: String
    /// The phone the Person has stored: a snapshot of their contact's, or the one the user typed.
    let storedPhone: String?
    /// Links the Person to their entry in Contacts, whose current phone is preferred over ``storedPhone`` (ADR-0009).
    let contactIdentifier: String?
    /// What the Person owes the user, one amount per currency. Empty for none, or while an amount isn't known.
    let owesYou: [Money]
    /// What the user owes the Person, one amount per currency.
    let youOwe: [Money]
    /// What the Expense was, when the text follows an Owes me reminder.
    let expense: String?

    /// One message per Person and wording, so a sheet shown for it is not shown twice.
    var id: String { "\(personName)\n\(body)" }
}

// MARK: Making one

extension TextReminder {
    /// The text for a Person's row in Show by people: what they owe the user and what the user owes them.
    init(_ entry: PersonDebtsAndLoans) {
        self.init(
            personName: entry.person.name, storedPhone: entry.person.phone?.nilIfBlank,
            contactIdentifier: entry.person.contactIdentifier, owesYou: entry.owesYou, youOwe: entry.youOwe,
            expense: nil
        )
    }

    /// The text for a reminder notification's "Text them" action, from what the notification carries
    /// (``TextThemPayload``). `person` is the Person it names, found in the store when they still are: their name,
    /// number and Contacts link as they are now win over what the notification was scheduled with. `nil` when the
    /// notification names no one.
    init?(_ payload: TextThemPayload, person: Person?) {
        guard let name = (person?.name ?? payload.personName).nilIfBlank else { return nil }
        let amounts = payload.outstanding.map { [$0] } ?? []
        self.init(
            personName: name, storedPhone: person?.phone?.nilIfBlank ?? payload.phone?.nilIfBlank,
            contactIdentifier: person?.contactIdentifier, owesYou: payload.youOwe ? [] : amounts,
            youOwe: payload.youOwe ? amounts : [], expense: payload.expense?.nilIfBlank
        )
    }

    /// The text for a reminder notification's "Text them" action, with the Person it names looked up in `context` by
    /// identity, so a rename since it was scheduled doesn't lose them.
    init?(_ payload: TextThemPayload, in context: ModelContext) throws {
        var person: Person?
        if let id = payload.person {
            var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.persistentModelID == id })
            descriptor.fetchLimit = 1
            person = try context.fetch(descriptor).first
        }
        self.init(payload, person: person)
    }
}

// MARK: The message and where it goes

extension TextReminder {
    /// The message, in the user's voice, naming what is owed with the app's money formatting: "Hi Alex, a reminder that
    /// you owe me $30.00 for Dinner.", "Hi Anna, I owe you $50.00.", or both directions in one message. While nothing is
    /// known to be owed but an Expense is named (an open amount), it names the Expense alone.
    var body: String {
        let name = personName
        switch (Self.list(owesYou), Self.list(youOwe)) {
        case let (theirs?, mine?):
            return String(localized: "Hi \(name), you owe me \(theirs), and I owe you \(mine).")
        case let (theirs?, nil):
            guard let expense else { return String(localized: "Hi \(name), a reminder that you owe me \(theirs).") }
            return String(localized: "Hi \(name), a reminder that you owe me \(theirs) for \(expense).")
        case (nil, let mine?):
            return String(localized: "Hi \(name), I owe you \(mine).")
        case (nil, nil):
            guard let expense else { return String(localized: "Hi \(name),") }
            return String(localized: "Hi \(name), a reminder that you owe me for \(expense).")
        }
    }

    /// The number to text: the Person's contact's current number when ``contactIdentifier`` resolves (the stored number
    /// while the contact still has it, otherwise the contact's first), and the ``storedPhone`` when it doesn't resolve,
    /// the contact has no number, access to Contacts is off or the Person isn't linked. `nil` when there is none.
    func phone(using lookup: some ContactLookup) async -> String? {
        if let contactIdentifier,
           let live = await lookup.contact(withIdentifier: contactIdentifier)?.phone(preferring: storedPhone) {
            return live
        }
        return storedPhone
    }

    /// Where the message goes: the compose sheet with the number and the message filled in, or, when texting isn't
    /// available (`canSendText` is false) or there is no number, copy or share. Doesn't ask `lookup` anything while
    /// texting isn't available. Never sends.
    func delivery(canSendText: Bool, using lookup: some ContactLookup) async -> TextDelivery {
        guard canSendText, let phone = await phone(using: lookup) else { return .copyOrShare(body: body) }
        return .compose(phone: phone, body: body)
    }

    /// `amounts` as one phrase in the user's language ("$30.00", "$30.00 and €5.00"), or `nil` for none.
    private static func list(_ amounts: [Money]) -> String? {
        amounts.isEmpty ? nil : ListFormatter.localizedString(byJoining: amounts.map { $0.formatted() })
    }
}
