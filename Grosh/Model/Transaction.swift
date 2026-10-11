import Foundation
import SwiftData

/// One dated movement of money into or out of one wallet, filed under one category.
@Model
final class Transaction {
    /// Signed effect on the wallet in cents: positive adds money, negative takes it away.
    var amountCents: Int = 0
    /// The ``CalendarDay`` as `yyyymmdd`.
    var dayRaw: Int = 0
    var note: String = ""
    /// The person the transaction involved ("With").
    var withName: String = ""
    var eventName: String = ""
    var isExcludedFromReport: Bool = false
    /// Set on a balance adjustment: the difference between the wallet's recorded and real balance. It never
    /// needs a Card, whatever its category.
    var isBalanceAdjustment: Bool = false
    /// Transactions sharing a link are related: the two halves of a transfer, or a Loan and its Debt Collections.
    var linkID: UUID?
    /// When the transaction was entered; orders transactions within a day.
    var createdAt: Date = Date.now
    /// On a Loan or Debt, the ``CalendarDay`` (as `yyyymmdd`) the user is reminded of it: its due date.
    var reminderDayRaw: Int?
    /// On a forgiven Loan or Debt, what was forgiven in cents, above zero: what was outstanding when it was forgiven
    /// (ADR-0004). `nil` while it isn't forgiven.
    var forgivenCents: Int?
    /// On a forgiven Loan or Debt, the ``CalendarDay`` (as `yyyymmdd`) it was forgiven on.
    var forgivenDayRaw: Int?
    var forgivenNote: String = ""
    /// When the transaction was moved to Recently Deleted, or `nil` while it isn't there. A transaction in Recently
    /// Deleted counts in no balance, list, search or report.
    var deletedAt: Date?
    /// Set on a transaction that went to Recently Deleted with its wallet, as part of that one item: it is restored
    /// with the wallet, never on its own.
    var deletedWithWallet: Bool = false

    var wallet: Wallet?
    var category: Category?
    var card: Card?
    /// On a forgiven Loan or Debt, the category the forgiven amount counts under in reports.
    var forgivenCategory: Category?

    init(
        amount: Money,
        day: CalendarDay,
        wallet: Wallet?,
        category: Category?,
        card: Card? = nil,
        note: String = ""
    ) {
        self.amountCents = amount.cents
        self.dayRaw = day.rawValue
        self.wallet = wallet
        self.category = category
        self.card = card
        self.note = note
    }

    var amount: Money { Money(cents: amountCents, currencyCode: wallet?.currencyCode ?? Money.defaultCurrencyCode) }

    var day: CalendarDay {
        get { CalendarDay(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }

    /// On a Loan or Debt, the day the user is reminded of it (its due date), or `nil` for no reminder.
    var reminderDay: CalendarDay? {
        get { reminderDayRaw.map(CalendarDay.init(rawValue:)) }
        set { reminderDayRaw = newValue?.rawValue }
    }
}
