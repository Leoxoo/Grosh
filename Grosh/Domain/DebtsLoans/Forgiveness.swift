import Foundation
import SwiftData

/// What the Forgive the rest sheet holds: the day whatever is still outstanding on a Loan or Debt is forgiven, without
/// any money moving or any transaction added, and the category the forgiven amount counts under in reports.
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
        self.category = try context.otherCategory(loanOrDebt.kind.forgivenType)
    }

    /// Expense for a forgiven Loan (the user gives the money up), Income for a forgiven Debt.
    var forgivenType: CategoryType { loanOrDebt.kind.forgivenType }

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

/// The mark a forgiven Loan or Debt carries (ADR-0004): how much was forgiven, when, and under which category it counts
/// in reports. Forgiving adds no transaction and never changes any balance; the original and its payments stay as
/// they are.
struct Forgiveness {
    /// What was forgiven, above zero: what was outstanding when it was forgiven.
    let amount: Money
    let day: CalendarDay
    /// The category the forgiven amount counts under in reports.
    let category: Category?
    let note: String
    /// A forgiven Loan or a forgiven Debt.
    let kind: LoanOrDebtKind

    /// How the forgiven amount counts in reports on ``day``: as income (above zero) for a forgiven Debt, as expense
    /// (below zero) for a forgiven Loan.
    var reportAmount: Money {
        Money(cents: kind == .debt ? amount.cents : -amount.cents, currencyCode: amount.currencyCode)
    }
}

extension Forgiveness {
    /// Marks the draft's Loan or Debt forgiven on its day: whatever is still outstanding, under the draft's category
    /// and with its note. Nothing is outstanding after, so it counts as settled. No transaction is added and no
    /// balance changes. Saves.
    @discardableResult
    static func record(_ draft: ForgiveDraft, in context: ModelContext) throws -> Forgiveness {
        try draft.loanOrDebt.settle(in: context, check: draft.validate(against:)) { current in
            guard let category = draft.category else { throw TransactionRuleError.missingCategory }
            let original = current.original
            original.forgivenCents = current.outstanding.cents
            original.forgivenDay = draft.day
            original.forgivenNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
            original.forgivenCategory = category
            guard let forgiveness = original.forgiveness else { throw DebtLoanRuleError.notALoanOrDebt }
            return forgiveness
        }
    }
}

extension Transaction {
    /// The mark this Loan or Debt carries once forgiven, or `nil` while it isn't (or for any other transaction).
    var forgiveness: Forgiveness? {
        guard let kind = loanOrDebtKind, let forgivenCents, let forgivenDay else { return nil }
        return Forgiveness(
            amount: Money(cents: forgivenCents, currencyCode: amount.currencyCode), day: forgivenDay,
            category: forgivenCategory, note: forgivenNote, kind: kind
        )
    }

    /// Whether this Loan or Debt was forgiven.
    var isForgiven: Bool { forgivenCents != nil }

    /// The day this Loan or Debt was forgiven on, or `nil` while it isn't forgiven.
    var forgivenDay: CalendarDay? {
        get { forgivenDayRaw.map(CalendarDay.init(rawValue:)) }
        set { forgivenDayRaw = newValue?.rawValue }
    }

    /// Takes the Forgiven mark off this Loan or Debt, so what was forgiven is outstanding again and stops counting in
    /// reports. Its payments stay as they are. Saves.
    func unforgive() throws {
        guard isLoanOrDebt else { throw DebtLoanRuleError.notALoanOrDebt }
        guard isForgiven else { throw DebtLoanRuleError.notForgiven }
        forgivenCents = nil
        forgivenDay = nil
        forgivenNote = ""
        forgivenCategory = nil
        try modelContext?.save()
    }
}
