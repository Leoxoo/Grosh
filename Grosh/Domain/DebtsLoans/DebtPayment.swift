import Foundation
import SwiftData

/// What the Record payment sheet holds: an amount collected on a Loan or repaid on a Debt, and its date. The part
/// above what is outstanding is an overpayment, filed as ordinary income (Loan) or expense (Debt).
struct DebtPaymentDraft {
    /// The Loan or Debt being paid, as it stood when the sheet opened.
    let loanOrDebt: LoanOrDebt
    /// The amount as typed, entered positive. Starts at what is outstanding, so paying in full is one tap.
    var entry: AmountEntry
    var day: CalendarDay
    var note = ""
    /// The category an overpayment is filed under: any category of ``overpaymentType``. Starts at Other Income for a
    /// Loan and Other Expense for a Debt.
    var overpaymentCategory: Category?

    /// A payment against `original`, a Loan or Debt, dated `day`. Throws when `original` is neither.
    init(settling original: Transaction, on day: CalendarDay) throws {
        guard let loanOrDebt = try LoanOrDebt(original) else { throw DebtLoanRuleError.notALoanOrDebt }
        self.loanOrDebt = loanOrDebt
        entry = AmountEntry(cents: loanOrDebt.outstanding.cents)
        self.day = day
        self.overpaymentCategory = try original.storeContext().otherCategory(loanOrDebt.kind.overpaymentType)
    }

    /// The amount is in the Loan or Debt's currency.
    var currencyCode: String { loanOrDebt.owed.currencyCode }

    /// Income for money collected beyond a Loan, Expense for money repaid beyond a Debt.
    var overpaymentType: CategoryType { loanOrDebt.kind.overpaymentType }

    /// The part of the amount above what is outstanding.
    var overpaid: Money { loanOrDebt.split(amount).overpaid }

    /// The overpayment as it moves the wallet: money in above a Loan, money out above a Debt.
    var signedOverpaid: Money {
        Money(cents: overpaid.cents * loanOrDebt.kind.paymentSign, currencyCode: overpaid.currencyCode)
    }

    /// Checks the payment against `standing`, the Loan or Debt as it is now, before anything is recorded: it must
    /// still be open, the amount above zero, and an overpayment filed under a category of ``overpaymentType``.
    func validate(against standing: LoanOrDebt) throws {
        guard !standing.isSettled else { throw DebtLoanRuleError.alreadySettled }
        guard amount.cents > 0 else { throw TransactionRuleError.missingAmount }
        guard standing.split(amount).overpaid.cents > 0 else { return }
        guard let overpaymentCategory else { throw TransactionRuleError.missingCategory }
        guard overpaymentCategory.type == overpaymentType else { throw DebtLoanRuleError.categoryDoesNotMatch }
    }

    /// Checks the payment against the Loan or Debt as it stood when the sheet opened.
    func validate() throws {
        try validate(against: loanOrDebt)
    }
}

/// What Record payment adds: the part that was owed, filed as a Debt Collection (Loan) or Repayment (Debt), and any
/// part above it as ordinary income or expense.
struct DebtPayment {
    /// The Debt Collection or Repayment, excluded from report.
    let payment: Transaction
    /// The part paid above what was outstanding, as ordinary income or expense. `nil` when nothing was overpaid.
    let overpayment: Transaction?
}

extension DebtPayment {
    /// Records the draft's payment on its day, in the Loan's or Debt's wallet and linked to it: up to what is
    /// outstanding as a Debt Collection or Repayment (excluded from report), and anything above it as ordinary
    /// income or expense in the draft's overpayment category. The original transaction keeps its amount and date.
    /// Saves.
    @discardableResult
    static func record(_ draft: DebtPaymentDraft, in context: ModelContext) throws -> DebtPayment {
        try draft.loanOrDebt.settle(check: draft.validate(against:)) { current in
            let paymentCategory = try context.lockedCategory(current.kind.paymentRole)
            let sign = current.kind.paymentSign
            let split = current.split(draft.amount)
            let payment = try current.addLinked(
                split.owed.cents * sign, filedUnder: paymentCategory,
                on: draft.day, note: draft.note, isExcludedFromReport: true
            )
            var overpayment: Transaction?
            if split.overpaid.cents > 0, let category = draft.overpaymentCategory {
                overpayment = try current.addLinked(
                    split.overpaid.cents * sign, filedUnder: category,
                    on: draft.day, note: draft.note, isExcludedFromReport: false
                )
            }
            return DebtPayment(payment: payment, overpayment: overpayment)
        }
    }
}

extension LoanOrDebt {
    /// Splits a payment of `amount` into the part that was owed (up to what is outstanding) and the part above it.
    func split(_ amount: Money) -> (owed: Money, overpaid: Money) {
        let owed = min(amount.cents, outstanding.cents)
        return (
            Money(cents: owed, currencyCode: amount.currencyCode),
            Money(cents: amount.cents - owed, currencyCode: amount.currencyCode)
        )
    }
}
