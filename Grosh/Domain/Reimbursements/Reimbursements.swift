import Foundation
import SwiftData

/// What a Reimbursement sheet holds: an amount, the day it was paid back and an optional note.
nonisolated struct ReimbursementDraft {
    /// The amount as typed: blank for a new one, the Reimbursement's own when editing.
    var entry: AmountEntry
    /// The currency of the Expense paid back.
    let currencyCode: String
    var day: CalendarDay
    var note = ""

    init(editing reimbursement: Reimbursement) {
        entry = AmountEntry(cents: reimbursement.amount.cents)
        currencyCode = reimbursement.amount.currencyCode
        day = reimbursement.day
        note = reimbursement.note
    }

    init(amount: Money, day: CalendarDay, note: String = "") {
        entry = AmountEntry(cents: amount.cents)
        currencyCode = amount.currencyCode
        self.day = day
        self.note = note
    }

    /// A new payback on `expense`, dated `day`, with nothing typed yet.
    init(payingBack expense: Transaction, on day: CalendarDay) {
        self.init(amount: Money(cents: 0, currencyCode: expense.amount.currencyCode), day: day)
    }

    func validate() throws {
        guard amount.cents > 0 else { throw ReimbursementRuleError.missingAmount }
    }
}

/// Why a Reimbursement can't be saved.
nonisolated enum ReimbursementRuleError: RuleRefusal, Equatable {
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
        case .missingAmount: String(localized: Strings.Common.enterAmountAboveZero)
        case .notAnExpense: String(localized: Strings.Reimbursements.notAnExpense)
        case .notADeposit: String(localized: Strings.Reimbursements.notADeposit)
        case .otherWallet: String(localized: Strings.Reimbursements.otherWallet)
        }
    }
}

extension Transaction {
    /// Whether the transaction is an Expense, so it can have Reimbursements and + Owes me
    /// (``isReimbursable(type:category:isBalanceAdjustment:sign:)``).
    var canBeReimbursed: Bool {
        Self.isReimbursable(
            type: category?.type, category: category, isBalanceAdjustment: isBalanceAdjustment,
            sign: amountCents.signum()
        )
    }

    /// The one rule for what can be paid back, read by a saved transaction (``canBeReimbursed``) and by the Add sheet
    /// (``TransactionDraft/offersOwesMe``) alike: money going out (`sign` below zero) under the Expense type. A
    /// transfer's outgoing half, a balance adjustment and a refund (an Expense that brought money in) aren't.
    nonisolated static func isReimbursable(
        type: CategoryType?, category: Category?, isBalanceAdjustment: Bool, sign: Int
    ) -> Bool {
        type == .expense && category?.isTransferHalf != true && !isBalanceAdjustment && sign < 0
    }

    /// The money paid back against this Expense, the earliest day first.
    var orderedReimbursements: [Reimbursement] {
        (reimbursements ?? []).sorted { ($0.dayRaw, $0.createdAt) < ($1.dayRaw, $1.createdAt) }
    }

    /// Adds its Reimbursements up again into ``reimbursedCents``, after one is added, edited, removed or moved to
    /// another transaction. Only the Reimbursement rules below change them, so they are the only callers. Doesn't save.
    fileprivate func recountReimbursements() {
        let total = (reimbursements ?? []).reduce(0) { $0 + $1.amountCents }
        changeCounted { $0.reimbursedCents = total }
    }

    /// What the transaction adds to or takes from its wallet in cents: its amount plus its Reimbursements. Balances, lists
    /// and reports read this, never ``amountCents``; only a Card's statement counts what the Card was charged.
    var netCents: Int { amountCents + reimbursedCents }

    /// ``netCents`` as money in its wallet's currency.
    var net: Money { Money(cents: netCents, currencyCode: amount.currencyCode) }
}

extension Reimbursement {
    /// Adds the draft as a Reimbursement of `expense`, entered now, recorded against `expectation` when one is given
    /// (ADR-0010). No transaction is made. Saves.
    @discardableResult
    static func add(
        _ draft: ReimbursementDraft, to expense: Transaction, for expectation: ExpectedReimbursement? = nil,
        in context: ModelContext
    ) throws -> Reimbursement {
        try draft.validate()
        guard expense.canBeReimbursed else { throw ReimbursementRuleError.notAnExpense }
        let reimbursement = Reimbursement(amountCents: 0, day: draft.day)
        context.insert(reimbursement)
        reimbursement.expense = expense
        reimbursement.expectation = expectation
        reimbursement.apply(draft)
        expense.recountReimbursements()
        try context.save()
        return reimbursement
    }

    /// Moves the entry onto `expense`, such as a part of a Split it was assigned to: both Expenses' nets follow.
    /// Doesn't save.
    func move(to expense: Transaction) {
        let previous = self.expense
        guard previous !== expense else { return }
        self.expense = expense
        previous?.reimbursements?.removeAll { $0 === self }
        previous?.recountReimbursements()
        expense.recountReimbursements()
    }

    func update(with draft: ReimbursementDraft) throws {
        try draft.validate()
        apply(draft)
        expense?.recountReimbursements()
        try saveToStore()
    }

    /// Removes the entry from its Expense, whose net falls back by its amount. Saves.
    func delete() throws {
        let context = try storeContext()
        try removeFromExpense()
        try context.save()
    }

    /// ``delete()`` without the save, for a caller that saves once after more changes.
    func removeFromExpense() throws {
        let context = try storeContext()
        let expense = expense
        expense?.reimbursements?.removeAll { $0 === self }
        expectation?.reimbursements?.removeAll { $0 === self }
        context.delete(self)
        expense?.recountReimbursements()
    }

    private func apply(_ draft: ReimbursementDraft) {
        amountCents = draft.amount.cents
        day = draft.day
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
