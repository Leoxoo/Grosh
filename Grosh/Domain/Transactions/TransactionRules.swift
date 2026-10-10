import Foundation
import SwiftData

extension Transaction {
    /// Records the draft as a new transaction, entered now. Saves.
    @discardableResult
    static func create(_ draft: TransactionDraft, in context: ModelContext) throws -> Transaction {
        try draft.validate()
        let transaction = Transaction(amount: Money(cents: 0), day: draft.day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.apply(draft)
        try context.save()
        return transaction
    }

    /// Saves an edited draft. The transaction keeps its place within its day. Nothing changes when the draft
    /// breaks a transaction rule.
    func update(with draft: TransactionDraft) throws {
        try draft.validate()
        apply(draft)
        try modelContext?.save()
    }

    private func apply(_ draft: TransactionDraft) {
        amountCents = draft.amount.cents * draft.sign
        day = draft.day
        wallet = draft.wallet
        category = draft.category
        card = draft.offersCard ? draft.card : nil
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        withName = draft.withName.trimmingCharacters(in: .whitespacesAndNewlines)
        isExcludedFromReport = draft.isExcludedFromReport
        reminderDay = draft.offersReminder ? draft.reminderDay : nil
    }
}

extension Category {
    /// How a transaction filed here moves its wallet: `1` adds the amount, `-1` takes it away. Expense takes
    /// money out and Income brings it in; a Loan (you lent) and a Repayment take it out, a Debt (you borrowed)
    /// and a Debt Collection bring it in.
    var sign: Int {
        switch lockedRole {
        case .loan, .repayment: return -1
        case .debt, .debtCollection: return 1
        default: return type == .expense ? -1 : 1
        }
    }
}
