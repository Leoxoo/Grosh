import Foundation
import SwiftData

/// Money someone paid back against an Expense, kept as an entry on that Expense and never as a transaction of its own.
/// The Expense's net is its amount plus its Reimbursements (``Transaction/netCents``).
@Model
final class Reimbursement {
    /// What was paid back in cents, above zero.
    var amountCents: Int = 0
    /// The ``CalendarDay`` as `yyyymmdd`.
    var dayRaw: Int = 0
    var note: String = ""
    /// When the entry was added; orders entries within a day.
    var createdAt: Date = Date.now

    /// The Expense it was paid back against. It goes with the Expense when that is removed for good.
    var expense: Transaction?
    /// The deposit it was moved in from, waiting in Recently Deleted: restoring the deposit undoes the move and removes
    /// this entry. `nil` for an entry typed in, and once the deposit is removed for good.
    var movedFrom: Transaction?

    init(amount: Money, day: CalendarDay, note: String = "") {
        self.amountCents = amount.cents
        self.dayRaw = day.rawValue
        self.note = note
    }

    var amount: Money { Money(cents: amountCents, currencyCode: expense?.amount.currencyCode ?? Money.defaultCurrencyCode) }

    var day: CalendarDay {
        get { CalendarDay(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }
}
