import Foundation
import SwiftData

/// A Loan (money the user lent) or a Debt (money the user borrowed), with the payments recorded against it: the
/// Debt Collections of a Loan, or the Repayments of a Debt (ADR-0003). The original transaction is never changed by
/// a payment; what is still owed is worked out from the payments linked to it.
struct LoanOrDebt {
    /// The Loan or Debt transaction itself.
    let original: Transaction
    /// The Debt Collections (of a Loan) or Repayments (of a Debt) sharing the original's link, newest first.
    let payments: [Transaction]

    /// `original` with the payments among `transactions` that share its link, or `nil` when it isn't a Loan or a
    /// Debt.
    init?(_ original: Transaction, among transactions: some Sequence<Transaction>) {
        guard let paymentRole = original.category?.lockedRole?.paymentRole else { return nil }
        self.original = original
        let link = original.linkID
        payments = link == nil ? [] : transactions
            .filter { $0.linkID == link && $0.category?.lockedRole == paymentRole }
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

    /// A Loan (money the user lent and gets back) rather than a Debt (money the user borrowed and pays back).
    var isLoan: Bool { original.category?.lockedRole == .loan }

    /// The category payments are filed under: Debt Collection for a Loan, Repayment for a Debt.
    var paymentRole: LockedRole? { original.category?.lockedRole?.paymentRole }

    /// How a payment moves the wallet: a Debt Collection brings money in (`1`), a Repayment takes it out (`-1`).
    var paymentSign: Int { isLoan ? 1 : -1 }

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

extension LockedRole {
    /// The category a payment against a transaction of this role is filed under: Debt Collection for a Loan,
    /// Repayment for a Debt. `nil` for every other role.
    var paymentRole: LockedRole? {
        switch self {
        case .loan: .debtCollection
        case .debt: .repayment
        default: nil
        }
    }
}

extension Category {
    /// Loan or Debt: the categories payments settle, and which need a With.
    var isLoanOrDebt: Bool { lockedRole == .loan || lockedRole == .debt }
}

extension Transaction {
    /// Whether this is a Loan or a Debt, which payments settle.
    var isLoanOrDebt: Bool { category?.isLoanOrDebt == true }

    /// Whether this is the ordinary expense or income a Loan or Debt adds beside a payment (``LoanOrDebt/addLinked``):
    /// what was paid above it, or the forgiven amount. It shares the Loan's or Debt's link, as no other expense or
    /// income does (a transfer half is filed under a transfer category).
    var isDebtWriteOff: Bool {
        guard linkID != nil, let category, !category.isTransferHalf else { return false }
        return category.type == .expense || category.type == .income
    }

    /// For a Loan or Debt, how much has not yet been collected or repaid. Zero for any other transaction.
    func outstanding(in context: ModelContext) throws -> Money {
        try LoanOrDebt(self, in: context)?.outstanding ?? Money(cents: 0, currencyCode: amount.currencyCode)
    }

    /// Whether this Loan or Debt has nothing outstanding. Any other transaction never is settled.
    func isSettled(in context: ModelContext) throws -> Bool {
        try LoanOrDebt(self, in: context)?.isSettled ?? false
    }

    /// Links `payment`, a Debt Collection (for a Loan) or Repayment (for a Debt) recorded without one, such as by an
    /// import, so it counts against this Loan or Debt and they show as each other's Related transactions. Only the
    /// links change. Saves.
    func linkPayment(_ payment: Transaction) throws {
        guard let paymentRole = category?.lockedRole?.paymentRole else { throw DebtLoanRuleError.notALoanOrDebt }
        guard payment.category?.lockedRole == paymentRole else { throw DebtLoanRuleError.paymentDoesNotMatch }
        payment.linkID = paymentLink()
        try modelContext?.save()
    }

    /// The link this Loan or Debt shares with its payments, made the first time one is recorded.
    fileprivate func paymentLink() -> UUID {
        if let linkID { return linkID }
        let link = UUID()
        linkID = link
        return link
    }
}
