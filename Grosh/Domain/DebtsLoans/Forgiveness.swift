import Foundation
import SwiftData

/// What the Forgive the rest sheet holds: the day whatever is still outstanding on a Loan or Debt is settled
/// without any money moving, and the category the forgiven amount appears under.
struct ForgiveDraft {
    /// The Loan or Debt being forgiven, as it stood when the sheet opened.
    let loanOrDebt: LoanOrDebt
    var day: CalendarDay
    var note = ""
    /// The category the forgiven amount is filed under: any category of ``forgivenType``. Starts at Other Expense
    /// for a Loan and Other Income for a Debt.
    var category: Category?

    /// Forgiving the rest of `original`, a Loan or Debt, on `day`. Throws when `original` is neither.
    init(forgiving original: Transaction, on day: CalendarDay, in context: ModelContext) throws {
        guard let loanOrDebt = try LoanOrDebt(original, in: context) else { throw DebtLoanRuleError.notALoanOrDebt }
        self.loanOrDebt = loanOrDebt
        self.day = day
        self.category = try context.lockedCategory(loanOrDebt.forgivenType == .expense ? .otherExpense : .otherIncome)
    }

    /// Expense for a forgiven Loan (the user gives the money up), Income for a forgiven Debt.
    var forgivenType: CategoryType { loanOrDebt.forgivenType }

    /// What is forgiven: everything still outstanding.
    var forgiven: Money { loanOrDebt.outstanding }

    /// Checks the forgive against `standing`, the Loan or Debt as it is now: it must still be open, and the
    /// forgiven amount filed under a category of ``forgivenType``.
    func validate(against standing: LoanOrDebt) throws {
        guard !standing.isSettled else { throw DebtLoanRuleError.alreadySettled }
        guard let category else { throw TransactionRuleError.missingCategory }
        guard category.type == forgivenType else { throw DebtLoanRuleError.categoryDoesNotMatch }
    }

    /// Whether Forgive can be enabled.
    var canSave: Bool { (try? validate(against: loanOrDebt)) != nil }
}

/// What Forgive the rest adds: a linked pair on one day that nets to zero. For a Loan, a Debt Collection of what was
/// outstanding (excluded from report) and an expense of the same amount; for a Debt, a Repayment and an income.
struct Forgiveness {
    /// The Debt Collection or Repayment that settles what was outstanding, excluded from report.
    let payment: Transaction
    /// The forgiven amount as ordinary expense (Loan) or income (Debt), which counts in reports.
    let forgiven: Transaction
}

extension Forgiveness {
    /// Settles whatever is still outstanding on the draft's Loan or Debt on its day, in its wallet and linked to
    /// it, without changing any balance. The original transaction keeps its amount and date. Saves.
    @discardableResult
    static func record(_ draft: ForgiveDraft, in context: ModelContext) throws -> Forgiveness {
        guard let current = try LoanOrDebt(draft.loanOrDebt.original, in: context),
              let paymentRole = current.paymentRole
        else { throw DebtLoanRuleError.notALoanOrDebt }
        try draft.validate(against: current)
        guard let category = draft.category else { throw TransactionRuleError.missingCategory }
        let cents = current.outstanding.cents * current.paymentSign
        let forgiveness = Forgiveness(
            payment: try current.addLinked(
                cents, filedUnder: try context.lockedCategory(paymentRole),
                on: draft.day, note: draft.note, isExcludedFromReport: true, in: context
            ),
            forgiven: try current.addLinked(
                -cents, filedUnder: category, on: draft.day, note: draft.note, isExcludedFromReport: false, in: context
            )
        )
        try context.save()
        return forgiveness
    }
}

extension LoanOrDebt {
    /// Expense for a forgiven Loan, Income for a forgiven Debt: the opposite of an overpayment.
    var forgivenType: CategoryType { isLoan ? .expense : .income }
}
