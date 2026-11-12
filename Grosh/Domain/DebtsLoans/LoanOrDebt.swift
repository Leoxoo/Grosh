import Foundation
import SwiftData

/// A Loan (money the user lent) or a Debt (money the user borrowed), with the payments recorded against it: the
/// Debt Collections of a Loan, or the Repayments of a Debt (ADR-0003), and its Forgiven mark once forgiven (ADR-0004).
/// The original transaction is never changed by a payment; what is still owed is worked out from the payments linked
/// to it. This is the one place Outstanding is worked out: Debts & Loans, the detail, the Home bell and the reminders
/// all read it from here.
struct LoanOrDebt: Equatable {
    /// The Loan or Debt transaction itself.
    let original: Transaction
    /// Which way the money went.
    let kind: LoanOrDebtKind
    /// The Debt Collections (of a Loan) or Repayments (of a Debt) sharing the original's link, newest first.
    let payments: [Transaction]

    /// `original` with the payments among `transactions` that share its link, or `nil` when it isn't a Loan or a
    /// Debt.
    init?(_ original: Transaction, among transactions: some Sequence<Transaction>) {
        guard let kind = original.loanOrDebtKind else { return nil }
        self.original = original
        self.kind = kind
        let link = original.linkID
        payments = link == nil ? [] : transactions
            .filter { $0.linkID == link && $0.isPayment(of: kind) }
            .inListOrder()
    }

    /// `original` with its payments, or `nil` when it isn't a Loan or a Debt.
    init?(_ original: Transaction, in context: ModelContext) throws {
        guard original.isLoanOrDebt else { return nil }
        self.init(original, among: try original.related(in: context))
    }

    /// The Person it is with: a Loan or Debt is with exactly one (ADR-0009, ``TransactionRuleError/tooManyWith``).
    var person: Person? { original.people?.first }

    /// What its row is titled: who it is with, or its category's name when nobody is named.
    var title: String { original.withName.isEmpty ? original.categoryName : original.withName }

    /// What the original lent or borrowed, above zero.
    var owed: Money { Money(cents: abs(original.amountCents), currencyCode: original.amount.currencyCode) }

    /// How much has been collected or repaid so far, above zero.
    var paid: Money {
        Money(cents: payments.reduce(0) { $0 + abs($1.amountCents) }, currencyCode: original.amount.currencyCode)
    }

    /// The Forgiven mark, once the rest was forgiven.
    var forgiveness: Forgiveness? { original.forgiveness }

    /// How much has not yet been collected, repaid or forgiven: the original minus its payments and what was forgiven,
    /// never below zero. Nothing once the rest was forgiven, unless a payment was deleted since: that part is
    /// outstanding again.
    var outstanding: Money {
        let forgiven = original.forgivenCents ?? 0
        return Money(cents: max(0, owed.cents - paid.cents - forgiven), currencyCode: original.amount.currencyCode)
    }

    /// Nothing is outstanding: paid in full, or forgiven.
    var isSettled: Bool { outstanding.cents == 0 }

    /// The one way something is recorded against a Loan or Debt, by Record payment or Forgive the rest: reads it again
    /// as it stands now (a payment may have been recorded since the sheet opened), lets `check` refuse, has `record`
    /// add the payment or the Forgiven mark to it, then saves.
    func settle<Recorded>(
        in context: ModelContext,
        check: (_ current: LoanOrDebt) throws -> Void,
        record: (_ current: LoanOrDebt) throws -> Recorded
    ) throws -> Recorded {
        guard let current = try LoanOrDebt(original, in: context) else { throw DebtLoanRuleError.notALoanOrDebt }
        try check(current)
        let recorded = try record(current)
        try context.save()
        return recorded
    }

    /// Adds a transaction linked to the original, in its wallet and with its With: a payment or an overpayment. The
    /// original only gains the link, the first time; its amount, date and every other field stay as they are.
    /// Doesn't save.
    func addLinked(
        _ cents: Int, filedUnder category: Category, on day: CalendarDay, note: String,
        isExcludedFromReport: Bool, in context: ModelContext
    ) throws -> Transaction {
        let transaction = Transaction.insert(
            Money(cents: cents), on: day, wallet: original.wallet, category: category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), in: context
        )
        transaction.setPeople(original.orderedPeople)
        transaction.isExcludedFromReport = isExcludedFromReport
        transaction.join(original, as: .loanOrDebt)
        return transaction
    }
}

/// Which way a Loan or Debt goes: money the user lent and gets back, or money the user borrowed and pays back.
nonisolated enum LoanOrDebtKind: Hashable, Sendable {
    case loan
    case debt

    /// The kind of a transaction filed under `role`, or `nil` when `role` is neither Loan nor Debt.
    init?(_ role: LockedRole?) {
        switch role {
        case .loan: self = .loan
        case .debt: self = .debt
        default: return nil
        }
    }

    /// The category payments are filed under: Debt Collection for a Loan, Repayment for a Debt.
    var paymentRole: LockedRole {
        switch self {
        case .loan: .debtCollection
        case .debt: .repayment
        }
    }

    /// How a payment moves the wallet: a Debt Collection brings money in (`1`), a Repayment takes it out (`-1`).
    var paymentSign: Int {
        switch self {
        case .loan: 1
        case .debt: -1
        }
    }

    /// Income for money collected beyond a Loan, Expense for money repaid beyond a Debt.
    var overpaymentType: CategoryType {
        switch self {
        case .loan: .income
        case .debt: .expense
        }
    }

    /// Expense for a forgiven Loan (the user gives the money up), Income for a forgiven Debt: the opposite of an
    /// overpayment.
    var forgivenType: CategoryType {
        switch self {
        case .loan: .expense
        case .debt: .income
        }
    }
}

extension Category {
    /// Loan or Debt: the categories payments settle, and which need a With.
    var isLoanOrDebt: Bool { LoanOrDebtKind(lockedRole) != nil }
}

extension Transaction {
    /// Whether this is a Loan or a Debt, which payments settle.
    var isLoanOrDebt: Bool { loanOrDebtKind != nil }

    var loanOrDebtKind: LoanOrDebtKind? { LoanOrDebtKind(category?.lockedRole) }

    /// Whether this is the ordinary expense or income a Loan or Debt adds beside a payment (``LoanOrDebt/addLinked``):
    /// what was paid above it, or a forgiven amount recorded before forgiving became a mark (ADR-0004). It is on the
    /// Loan's or Debt's link (ADR-0012).
    var isDebtWriteOff: Bool { linkKind == .loanOrDebt && category?.type.isUserManaged == true }

    /// Whether this is a payment of a Loan or Debt of `kind`: a Debt Collection of a Loan, or a Repayment of a Debt.
    func isPayment(of kind: LoanOrDebtKind) -> Bool { category?.lockedRole == kind.paymentRole }

    /// The kind of Loan or Debt this pays: Loan for a Debt Collection, Debt for a Repayment, `nil` for anything else.
    var paidLoanOrDebtKind: LoanOrDebtKind? {
        [LoanOrDebtKind.loan, .debt].first { isPayment(of: $0) }
    }

    /// Whether this is a Debt Collection or Repayment on the link of a Loan or Debt that is forgiven. Restoring such a
    /// payment from Recently Deleted would count it a second time, since the forgiven amount already settles what it
    /// paid (ADR-0004). Reads the transactions on its link.
    func paysForgivenLoanOrDebt(in context: ModelContext) throws -> Bool {
        guard let kind = paidLoanOrDebtKind, linkKind == .loanOrDebt else { return false }
        return try context.fetch(linkedTransactions).contains { $0.isForgiven && $0.loanOrDebtKind == kind }
    }

    /// Its payments, those in Recently Deleted too: restoring one brings it back against this Loan or Debt, so until
    /// then it still holds the wallet, category and lowest amount in place (``TransactionDraft/isLockedByPayments``).
    /// Empty for anything but a Loan or Debt with a link.
    func paymentsWithRecentlyDeleted(in context: ModelContext) throws -> [Transaction] {
        guard let kind = loanOrDebtKind, let link = linkID else { return [] }
        let linked = FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID == link })
        return try context.fetch(linked).filter { $0.isPayment(of: kind) }
    }

    /// Links `payment`, a Debt Collection (for a Loan) or Repayment (for a Debt) recorded without one, such as by an
    /// import, so it counts against this Loan or Debt and they show as each other's Related transactions. Only the
    /// links change. Doesn't save: an import links many and saves once.
    func linkPayment(_ payment: Transaction) throws {
        guard let kind = loanOrDebtKind else { throw DebtLoanRuleError.notALoanOrDebt }
        guard payment.isPayment(of: kind) else { throw DebtLoanRuleError.paymentDoesNotMatch }
        payment.join(self, as: .loanOrDebt)
    }

    /// Whether `payment` pays this Loan or Debt back in one go: a Debt Collection for a Loan or a Repayment for a
    /// Debt, in its wallet, for its whole amount, and dated on or after it. How an import, which brings payments
    /// without their links, finds the Loan or Debt to link one to.
    func isPaidBackInFull(by payment: Transaction) -> Bool {
        guard let kind = loanOrDebtKind else { return false }
        return payment.isPayment(of: kind) && payment.wallet == wallet
            && payment.amountCents == -amountCents && payment.dayRaw >= dayRaw
    }
}
