import Foundation
import SwiftData

/// The part of an Expense that one Person is yet to pay back ("Owes me"), kept as a record of its own beside the Expense
/// (ADR-0010). It counts in no balance and no report: the Expense stays at its full amount until money comes back, and
/// money that comes back is a Reimbursement on the Expense (ADR-0008) or, paid into another wallet, a linked
/// transaction there.
@Model
final class ExpectedReimbursement {
    /// What the Person is expected to pay back in cents, above zero, or `nil` for an open amount: the user doesn't know
    /// yet how much, shown as `?`. An open amount is left out of totals.
    var amountCents: Int?
    /// The ``CalendarDay`` (as `yyyymmdd`) the user is reminded to ask for the money, or `nil` for no reminder.
    var reminderDayRaw: Int?
    /// The ``CalendarDay`` (as `yyyymmdd`) the user forgave it on, or `nil` while it isn't forgiven. Forgiving adds no
    /// transaction and changes no balance or report, as it never counted in either (ADR-0004).
    var forgivenDayRaw: Int?
    var forgivenNote: String = ""
    /// The ``CalendarDay`` (as `yyyymmdd`) the user closed an open-amount expectation by hand, or `nil`.
    var closedDayRaw: Int?
    /// When the expectation was made; orders the expectations of one Expense.
    var createdAt: Date = Date.now

    /// The Expense the Person is to pay back part of. The expectation goes with it: to Recently Deleted and back, and
    /// for good.
    var expense: Transaction?
    var person: Person?

    /// The money paid back in the Expense's own wallet that was recorded against this expectation. They stay on the
    /// Expense if the expectation goes.
    @Relationship(deleteRule: .nullify, inverse: \Reimbursement.expectation)
    var reimbursements: [Reimbursement]? = []
    /// The money paid back into another wallet that was recorded against this expectation: real transactions there,
    /// linked to the Expense like the halves of a transfer (ADR-0010).
    @Relationship(deleteRule: .nullify, inverse: \Transaction.paidExpectation)
    var paybacks: [Transaction]? = []

    init(amountCents: Int? = nil, reminderDay: CalendarDay? = nil) {
        self.amountCents = amountCents
        self.reminderDayRaw = reminderDay?.rawValue
    }
}
