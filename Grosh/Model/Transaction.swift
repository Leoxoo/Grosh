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
    /// The names of the transaction's ``people`` ("With"), joined with `; ` and ordered by name. A copy kept beside
    /// them, so a list, a search or an export reads the With without reading the ``people`` relationship one
    /// transaction at a time. ``setPeople(_:usedAt:)`` keeps it in step. Before ADR-0009 this was the With itself, a
    /// typed name; ``Person/migrateWithNames(in:)`` turns those into people.
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
    /// Set on a transaction a varying Bill made until its real amount is entered. Its amount is an estimate, the average
    /// of recent transactions in its category. It counts in balances and reports like any transaction.
    var isEstimated: Bool = false
    /// On an Estimated transaction, the ``CalendarDay`` (as `yyyymmdd`) the user is reminded to enter its real amount.
    var estimateReminderDayRaw: Int?
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
    /// The Recurring transaction that made this one, or that the user attached it to. `nil` for an ordinary one.
    var recurring: RecurringTransaction?
    /// On a forgiven Loan or Debt, the category the forgiven amount counts under in reports.
    var forgivenCategory: Category?
    /// The people in With (ADR-0009): any number, except on a Loan or Debt, which has exactly one. Unordered in the
    /// store; ``orderedPeople`` lists them by name. Set them with ``setPeople(_:usedAt:)``, never directly, so
    /// ``withName`` follows.
    var people: [Person]? = []
    /// On an Expense, what its Reimbursements add up to in cents: zero when it has none. Kept beside them, so a balance
    /// reads a transaction's net (``netCents``) without reading its Reimbursements one transaction at a time.
    /// ``recountReimbursements()`` keeps it in step whenever one is added, edited, removed or moved.
    var reimbursedCents: Int = 0
    /// On an Expense, the money paid back against it. They go with it: to Recently Deleted and back, and for good.
    @Relationship(deleteRule: .cascade, inverse: \Reimbursement.expense)
    var reimbursements: [Reimbursement]? = []
    /// On a deposit moved into an Expense, the Reimbursement it became. Restoring the deposit removes it; removing the
    /// deposit for good leaves it on the Expense.
    @Relationship(deleteRule: .nullify, inverse: \Reimbursement.movedFrom)
    var movedIntoReimbursements: [Reimbursement]? = []
    /// On an Expense, what the people in With are yet to pay back (ADR-0010). They count in no balance or report, and
    /// go with the Expense: to Recently Deleted and back, and for good.
    @Relationship(deleteRule: .cascade, inverse: \ExpectedReimbursement.expense)
    var expectations: [ExpectedReimbursement]? = []
    /// On an Expense, whether money was ever paid back into another wallet against it (ADR-0010). Only an Expense with
    /// it set reads its paybacks to work out its net in the Total (``totalViewNetCents``), so the rest never walk a
    /// relationship. Set when the first payback is recorded and never cleared, so it can read true for an Expense whose
    /// paybacks are gone, which only costs a look.
    var hasPaybacksElsewhere: Bool = false
    /// On a payback recorded into another wallet, the Expected reimbursement it was paid against, or `nil` when no one
    /// was expected to pay.
    var paidExpectation: ExpectedReimbursement?
    /// On a payback recorded into another wallet, the Expense it paid back (ADR-0010).
    var paidBackExpense: Transaction?
    /// On an Expense, the money paid back into other wallets against it, Recently Deleted ones included. Read through
    /// ``paybacksElsewhere``.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.paidBackExpense)
    var paybacks: [Transaction]? = []

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

    /// On an Estimated transaction, the day the user is reminded to enter its real amount, or `nil` for no reminder.
    var estimateReminderDay: CalendarDay? {
        get { estimateReminderDayRaw.map(CalendarDay.init(rawValue:)) }
        set { estimateReminderDayRaw = newValue?.rawValue }
    }
}
