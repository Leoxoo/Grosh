import Foundation
import SwiftData

/// What a Reimbursement sheet holds: an amount, the day it was paid back and an optional note.
nonisolated struct ReimbursementDraft {
    var amount = Money(cents: 0)
    var day: CalendarDay
    var note = ""

    /// The entry as it is now, ready to edit.
    init(editing reimbursement: Reimbursement) {
        amount = reimbursement.amount
        day = reimbursement.day
        note = reimbursement.note
    }

    init(amount: Money = Money(cents: 0), day: CalendarDay, note: String = "") {
        self.amount = amount
        self.day = day
        self.note = note
    }

    /// Checks the draft against the Reimbursement rules before anything is saved.
    func validate() throws {
        guard amount.cents > 0 else { throw ReimbursementRuleError.missingAmount }
    }
}

/// Why a Reimbursement can't be saved.
nonisolated enum ReimbursementRuleError: Error, Equatable {
    /// The amount paid back must be above zero.
    case missingAmount
    /// Only an Expense can be paid back.
    case notAnExpense
    /// Only money that came in can be moved into an Expense.
    case notADeposit
    /// Only money that came into the Expense's own wallet can be moved into it.
    case otherWallet
}

extension ReimbursementRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAmount: String(localized: "Enter an amount above zero.")
        case .notAnExpense: String(localized: "Only an Expense can be reimbursed.")
        case .notADeposit: String(localized: "Only money that came in can be moved into an Expense.")
        case .otherWallet: String(localized: "Only money that came into the Expense's own wallet can be moved into it.")
        }
    }
}

extension Transaction {
    /// Whether the transaction is an Expense, so it can have Reimbursements: money going out under an Expense category.
    /// A transfer's outgoing half, a balance adjustment and a refund aren't.
    var canBeReimbursed: Bool {
        category?.type == .expense && category?.isTransferHalf != true && !isBalanceAdjustment && amountCents < 0
    }

    /// The money paid back against this Expense, the earliest day first.
    var orderedReimbursements: [Reimbursement] {
        (reimbursements ?? []).sorted { ($0.dayRaw, $0.createdAt) < ($1.dayRaw, $1.createdAt) }
    }

    /// Adds its Reimbursements up again into ``reimbursedCents``, after one is added, edited, removed or moved to
    /// another transaction. Doesn't save.
    func recountReimbursements() {
        reimbursedCents = (reimbursements ?? []).reduce(0) { $0 + $1.amountCents }
    }

    /// What the transaction adds to or takes from its wallet in cents: its amount plus its Reimbursements. Balances, lists
    /// and reports read this, never ``amountCents``; only a Card's statement counts what the Card was charged.
    var netCents: Int { amountCents + reimbursedCents }

    /// ``netCents`` as money in its wallet's currency.
    var net: Money { Money(cents: netCents, currencyCode: amount.currencyCode) }
}

extension Reimbursement {
    /// Adds the draft as a Reimbursement of `expense`, entered now. No transaction is made. Saves.
    @discardableResult
    static func add(_ draft: ReimbursementDraft, to expense: Transaction, in context: ModelContext) throws -> Reimbursement {
        try draft.validate()
        guard expense.canBeReimbursed else { throw ReimbursementRuleError.notAnExpense }
        let reimbursement = Reimbursement(amount: Money(cents: 0), day: draft.day)
        context.insert(reimbursement)
        reimbursement.expense = expense
        reimbursement.apply(draft)
        expense.recountReimbursements()
        try context.save()
        return reimbursement
    }

    /// Saves an edited draft. Nothing changes when the draft breaks a Reimbursement rule.
    func update(with draft: ReimbursementDraft) throws {
        try draft.validate()
        apply(draft)
        expense?.recountReimbursements()
        try modelContext?.save()
    }

    /// Removes the entry from its Expense, whose net falls back by its amount. Saves.
    func delete() throws {
        guard let context = modelContext else { return }
        removeFromExpense()
        try context.save()
    }

    /// ``delete()`` without the save, for a caller that saves once after more changes.
    func removeFromExpense() {
        guard let context = modelContext else { return }
        let expense = expense
        expense?.reimbursements?.removeAll { $0 === self }
        context.delete(self)
        expense?.recountReimbursements()
    }

    private func apply(_ draft: ReimbursementDraft) {
        amountCents = draft.amount.cents
        day = draft.day
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
