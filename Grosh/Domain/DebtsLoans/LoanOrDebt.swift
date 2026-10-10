import Foundation
import SwiftData

/// A Loan (money the user lent) or a Debt (money the user borrowed), with the payments recorded against it: the
/// Debt Collections of a Loan, or the Repayments of a Debt (ADR-0003). The original transaction is never changed by
/// a payment; what is still owed is worked out from the payments linked to it. This is the one place Outstanding is
/// worked out: Debts & Loans, the detail, the Home bell and the reminders all read it from here.
struct LoanOrDebt {
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
            .filter { $0.linkID == link && $0.category?.lockedRole == kind.paymentRole }
            .inListOrder()
    }

    /// `original` with its payments, or `nil` when it isn't a Loan or a Debt.
    init?(_ original: Transaction, in context: ModelContext) throws {
        guard original.isLoanOrDebt else { return nil }
        self.init(original, among: try original.related(in: context))
    }

    /// What the original lent or borrowed, above zero.
    var owed: Money { Money(cents: abs(original.amountCents), currencyCode: original.amount.currencyCode) }

    /// How much has been collected or repaid so far, above zero.
    var paid: Money {
        Money(cents: payments.reduce(0) { $0 + abs($1.amountCents) }, currencyCode: original.amount.currencyCode)
    }

    /// How much has not yet been collected or repaid: the original minus its payments, never below zero.
    var outstanding: Money {
        Money(cents: max(0, owed.cents - paid.cents), currencyCode: original.amount.currencyCode)
    }

    /// Nothing is outstanding.
    var isSettled: Bool { outstanding.cents == 0 }

    /// The one way something is recorded against a Loan or Debt, by Record payment or Forgive the rest: reads it again
    /// as it stands now (a payment may have been recorded since the sheet opened), lets `check` refuse, has `record`
    /// add the linked transactions to it, given the category its payments are filed under, then saves.
    func settle<Recorded>(
        in context: ModelContext,
        check: (_ current: LoanOrDebt) throws -> Void,
        record: (_ current: LoanOrDebt, _ paymentCategory: Category) throws -> Recorded
    ) throws -> Recorded {
        guard let current = try LoanOrDebt(original, in: context) else { throw DebtLoanRuleError.notALoanOrDebt }
        try check(current)
        let recorded = try record(current, try context.lockedCategory(kind.paymentRole))
        try context.save()
        return recorded
    }

    /// Adds a transaction linked to the original, in its wallet and with its With: a payment, an overpayment, or
    /// half of a forgive. The original only gains the link, the first time; its amount, date and every other
    /// field stay as they are. Doesn't save.
    func addLinked(
        _ cents: Int, filedUnder category: Category, on day: CalendarDay, note: String,
        isExcludedFromReport: Bool, in context: ModelContext
    ) throws -> Transaction {
        let link = original.paymentLink()
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = original.wallet
        transaction.category = category
        transaction.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        transaction.withName = original.withName
        transaction.isExcludedFromReport = isExcludedFromReport
        transaction.linkID = link
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

    /// Loan or Debt, or `nil` for any other transaction.
    var loanOrDebtKind: LoanOrDebtKind? { LoanOrDebtKind(category?.lockedRole) }

    /// Whether this is the ordinary expense or income a Loan or Debt adds beside a payment (``LoanOrDebt/addLinked``):
    /// what was paid above it, or the forgiven amount. It shares the Loan's or Debt's link, as no other expense or
    /// income does (a transfer half is filed under a transfer category).
    var isDebtWriteOff: Bool {
        guard linkID != nil, let category, !category.isTransferHalf else { return false }
        return category.type == .expense || category.type == .income
    }

    /// Links `payment`, a Debt Collection (for a Loan) or Repayment (for a Debt) recorded without one, such as by an
    /// import, so it counts against this Loan or Debt and they show as each other's Related transactions. Only the
    /// links change. Saves.
    func linkPayment(_ payment: Transaction) throws {
        try linkPaymentWithoutSaving(payment)
        try modelContext?.save()
    }

    /// ``linkPayment(_:)`` without the save, for a caller that saves once after linking many, such as an import.
    func linkPaymentWithoutSaving(_ payment: Transaction) throws {
        guard let kind = loanOrDebtKind else { throw DebtLoanRuleError.notALoanOrDebt }
        guard payment.category?.lockedRole == kind.paymentRole else { throw DebtLoanRuleError.paymentDoesNotMatch }
        payment.linkID = paymentLink()
    }

    /// Whether `payment` pays this Loan or Debt back in one go: a Debt Collection for a Loan or a Repayment for a
    /// Debt, in its wallet, for its whole amount, and dated on or after it. How an import, which brings payments
    /// without their links, finds the Loan or Debt to link one to.
    func isPaidBackInFull(by payment: Transaction) -> Bool {
        guard let kind = loanOrDebtKind else { return false }
        return payment.category?.lockedRole == kind.paymentRole && payment.wallet == wallet
            && payment.amountCents == -amountCents && payment.dayRaw >= dayRaw
    }

    /// The link this Loan or Debt shares with its payments, made the first time one is recorded.
    fileprivate func paymentLink() -> UUID {
        if let linkID { return linkID }
        let link = UUID()
        linkID = link
        return link
    }
}
