import Foundation
import SwiftData

/// What the Record payment sheet holds: an amount collected on a Loan or repaid on a Debt, and its date. The part
/// above what is outstanding is an overpayment, filed as ordinary income (Loan) or expense (Debt).
struct DebtPaymentDraft {
    /// The Loan or Debt being paid, as it stood when the sheet opened.
    let loanOrDebt: LoanOrDebt
    /// Entered positive. Starts at what is outstanding, so paying in full is one tap.
    var amount: Money
    var day: CalendarDay
    var note = ""
    /// The category an overpayment is filed under: any category of ``overpaymentType``. Starts at Other Income for a
    /// Loan and Other Expense for a Debt.
    var overpaymentCategory: Category?

    /// A payment against `original`, a Loan or Debt, dated `day`. Throws when `original` is neither.
    init(settling original: Transaction, on day: CalendarDay, in context: ModelContext) throws {
        guard let loanOrDebt = try LoanOrDebt(original, in: context) else { throw DebtLoanRuleError.notALoanOrDebt }
        self.loanOrDebt = loanOrDebt
        self.amount = loanOrDebt.outstanding
        self.day = day
        self.overpaymentCategory = try context.otherCategory(loanOrDebt.kind.overpaymentType)
    }

    /// Income for money collected beyond a Loan, Expense for money repaid beyond a Debt.
    var overpaymentType: CategoryType { loanOrDebt.kind.overpaymentType }

    /// The part of the amount above what is outstanding.
    var overpaid: Money { loanOrDebt.split(amount).overpaid }

    /// Checks the payment against `standing`, the Loan or Debt as it is now, before anything is recorded: it must
    /// still be open, the amount above zero, and an overpayment filed under a category of ``overpaymentType``.
    func validate(against standing: LoanOrDebt) throws {
        guard !standing.isSettled else { throw DebtLoanRuleError.alreadySettled }
        guard amount.cents > 0 else { throw TransactionRuleError.missingAmount }
        guard standing.split(amount).overpaid.cents > 0 else { return }
        guard let overpaymentCategory else { throw TransactionRuleError.missingCategory }
        guard overpaymentCategory.type == overpaymentType else { throw DebtLoanRuleError.categoryDoesNotMatch }
    }

    /// Whether Save can be enabled.
    var canSave: Bool { (try? validate(against: loanOrDebt)) != nil }
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
        try draft.loanOrDebt.settle(in: context, check: draft.validate(against:)) { current, paymentCategory in
            let sign = current.kind.paymentSign
            let split = current.split(draft.amount)
            let payment = try current.addLinked(
                split.owed.cents * sign, filedUnder: paymentCategory,
                on: draft.day, note: draft.note, isExcludedFromReport: true, in: context
            )
            var overpayment: Transaction?
            if split.overpaid.cents > 0, let category = draft.overpaymentCategory {
                overpayment = try current.addLinked(
                    split.overpaid.cents * sign, filedUnder: category,
                    on: draft.day, note: draft.note, isExcludedFromReport: false, in: context
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
