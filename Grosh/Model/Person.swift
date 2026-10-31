import Foundation
import SwiftData

/// Someone a transaction involved, such as who the user ate with or who a Loan was given to: a name with an optional
/// phone, a hidden flag and the date they were last used. People and places are the same thing (ADR-0009).
///
/// Names are unique ignoring case, but only in app logic (``Person/add(named:phone:in:)``); the store enforces nothing
/// (ADR-0001).
@Model
final class Person {
    var name: String = ""
    /// The phone number as the user typed it, or `nil` for none.
    var phone: String?
    /// Set by Hide: the Person is left out of the With menu's Previous section but keeps their name and their place on
    /// every transaction. Typing their name again clears it.
    var isHidden: Bool = false
    /// When the Person was last chosen in With; orders Previous, the latest first.
    var lastUsedAt: Date = Date.now
    /// Links the Person to an entry in the user's Contacts (ADR-0009), set by picking a contact in the With menu
    /// (``Person/add(_:phone:in:)``). ``name`` and ``phone`` are snapshots of that contact, refreshed while it resolves.
    var contactIdentifier: String?

    /// The transactions the Person is in With on, Recently Deleted ones included. Many people can share a transaction.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.people)
    var transactions: [Transaction]? = []

    /// What the Person is yet to pay back (ADR-0010), Recently Deleted Expenses' included. Show by people reads it.
    @Relationship(deleteRule: .nullify, inverse: \ExpectedReimbursement.person)
    var expectations: [ExpectedReimbursement]? = []

    init(name: String, phone: String? = nil, lastUsedAt: Date = Date.now) {
        self.name = name
        self.phone = phone
        self.lastUsedAt = lastUsedAt
    }
}
