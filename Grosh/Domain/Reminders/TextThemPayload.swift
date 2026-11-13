import Foundation
import SwiftData

/// What a Loan, Debt or Owes me reminder notification carries for its "Text them" action (``TextReminder``, ADR-0009,
/// ADR-0010): the Person as they were when it was scheduled, and what is owed which way. It is kept in the
/// notification's user info, encoded under ``userInfoKey``.
nonisolated struct TextThemPayload: Codable, Hashable, Sendable {
    /// The Person the reminder names, looked up in the store again when the action is tapped.
    let person: PersistentIdentifier?
    let personName: String
    /// The Person's phone number when the reminder was scheduled, used when they are no longer in the store.
    let phone: String?
    /// What the Expense was, for an Owes me reminder.
    let expense: String?
    /// What is outstanding, or `nil` for an open amount.
    let outstanding: Money?
    /// Whether the user owes the Person (a Debt) rather than the Person the user.
    let youOwe: Bool

    init(
        person: PersistentIdentifier?, personName: String, phone: String?, expense: String? = nil,
        outstanding: Money?, youOwe: Bool = false
    ) {
        self.person = person
        self.personName = personName
        self.phone = phone
        self.expense = expense
        self.outstanding = outstanding
        self.youOwe = youOwe
    }
}

nonisolated extension TextThemPayload {
    /// The key in a notification's user info that holds the payload.
    static let userInfoKey = "grosh.text-them"

    /// The user info a notification carries it in.
    func userInfo() throws -> [String: Data] {
        [Self.userInfoKey: try JSONEncoder().encode(self)]
    }

    /// The payload a notification's `userInfo` carries, or `nil` when it carries none.
    init?(userInfo: [AnyHashable: Any]) throws {
        guard let data = userInfo[Self.userInfoKey] as? Data else { return nil }
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}
