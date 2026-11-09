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
    /// Transactions sharing a link are related: the two halves of a transfer, the parts of a Split, a Loan or Debt
    /// and what is recorded against it, or an Expense and its paybacks into other wallets. ``linkKind`` says which.
    /// Set through ``link(_:as:)``, ``join(_:as:)`` and ``leaveLink()``, so the two never disagree (ADR-0012).
    private(set) var linkID: UUID?
    /// The ``LinkKind``'s raw value, `nil` while the transaction is on no link (ADR-0012).
    private(set) var linkKindRaw: String?
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
    /// The Reimbursement rules recount it whenever one is added, edited, removed or moved, so no caller has to.
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
    /// relationship. Set when the first payback is recorded, and cleared with the Expense's link once the last one is
    /// removed for good: one waiting in Recently Deleted still holds the Expense's wallet.
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

    /// A transaction in no context yet, with no wallet, category or Card.
    /// ``insert(_:on:wallet:category:card:note:in:)`` is how one is made.
    private init(amount: Money, day: CalendarDay, note: String) {
        self.amountCents = amount.cents
        self.dayRaw = day.rawValue
        self.note = note
    }

    /// Makes a transaction of `amount` on `day` in `context`, in `wallet`, filed under `category` and paid with `card`.
    /// It is inserted before its relationships are set: SwiftData relates two models only once both are in the same
    /// context. Doesn't save.
    @discardableResult
    static func insert(
        _ amount: Money,
        on day: CalendarDay,
        wallet: Wallet?,
        category: Category?,
        card: Card? = nil,
        note: String = "",
        in context: ModelContext
    ) -> Transaction {
        let transaction = Transaction(amount: amount, day: day, note: note)
        context.insert(transaction)
        transaction.wallet = wallet
        transaction.category = category
        transaction.card = card
        return transaction
    }

    var amount: Money { Money(cents: amountCents, currencyCode: wallet.currencyCodeOrDefault) }

    var day: CalendarDay {
        get { CalendarDay(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }

    /// Whether the transaction is in Recently Deleted.
    var isInRecentlyDeleted: Bool { deletedAt != nil }

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

/// What a link joins (ADR-0012). Every transaction on one link has the same kind.
nonisolated enum LinkKind: String, CaseIterable, Sendable {
    /// The two halves of a Transfer (ADR-0002).
    case transfer
    /// The parts of a Split (ADR-0007).
    case split
    /// A Loan or Debt, its Debt Collections or Repayments, and what it writes off beside them (ADR-0003).
    case loanOrDebt
    /// An Expense and the money paid back into other wallets against it (ADR-0010).
    case payback
}

extension Transaction {
    /// What the transaction's link joins, or `nil` while it is on none (ADR-0012).
    var linkKind: LinkKind? { linkKindRaw.flatMap(LinkKind.init(rawValue:)) }

    /// Puts `transactions` on one new link of `kind`, taking each off any link it was on. Doesn't save.
    static func link(_ transactions: some Sequence<Transaction>, as kind: LinkKind) {
        let link = UUID()
        for transaction in transactions {
            transaction.linkID = link
            transaction.linkKindRaw = kind.rawValue
        }
    }

    /// Puts this transaction on `other`'s link, which is made first, of `kind`, when `other` is on none. Doesn't save.
    func join(_ other: Transaction, as kind: LinkKind) {
        if other.linkID == nil {
            Self.link([other], as: kind)
        }
        linkID = other.linkID
        linkKindRaw = other.linkKindRaw
    }

    /// Takes the transaction off its link. Doesn't save.
    func leaveLink() {
        linkID = nil
        linkKindRaw = nil
    }

    /// What the names in ``withName`` are joined with.
    static var withSeparator: String { "; " }

    /// The people in With, by name.
    var orderedPeople: [Person] {
        Self.ordered(people ?? [])
    }

    /// `people` in the order With lists them: by name.
    static func ordered(_ people: [Person]) -> [Person] {
        people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// How With names `people`, as ``withName`` keeps it: by name, joined with ``withSeparator``.
    static func withName(of people: [Person]) -> String {
        ordered(people).map(\.name).joined(separator: withSeparator)
    }

    /// Makes ``withName`` the names of the people in With again, after a name changed (ADR-0009). Doesn't save.
    func refreshWithName() {
        withName = Self.withName(of: people ?? [])
    }
}
