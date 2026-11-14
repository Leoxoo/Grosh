import Foundation
import SwiftData

extension Transaction {
    /// Records the draft as a new transaction, entered now. Saves.
    @discardableResult
    static func create(_ draft: TransactionDraft, in context: ModelContext) throws -> Transaction {
        try draft.validate()
        let transaction = Transaction.insert(cents: 0, on: draft.day, wallet: nil, category: nil, in: context)
        try transaction.apply(draft)
        try context.save()
        return transaction
    }

    /// The transaction keeps its place within its day. Saves.
    func update(with draft: TransactionDraft) throws {
        try draft.validate()
        // Editing the amount confirms an Estimated transaction. Only the amount's size counts, not its direction.
        let amountChanged = abs(amountCents) != draft.amount.cents
        try apply(draft)
        if amountChanged {
            clearEstimate()
        }
        try saveToStore()
    }

    private func apply(_ draft: TransactionDraft) throws {
        changeCounted {
            $0.amountCents = draft.amount.cents * draft.sign
            $0.day = draft.day
            $0.wallet = draft.wallet
        }
        category = draft.category
        card = draft.offersCard ? draft.card : nil
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        setPeople(draft.people)
        try setExpectations(draft.owes)
        isExcludedFromReport = draft.isExcludedFromReport
        reminderDay = draft.offersReminder ? draft.reminderDay : nil
    }
}

extension Category {
    /// How a transaction filed here moves its wallet: `1` adds the amount, `-1` takes it away. A Loan or Debt moves it
    /// as ``LoanOrDebtKind/sign`` says and a Debt Collection or Repayment as ``LoanOrDebtKind/paymentSign`` says;
    /// anything else as its type does (``CategoryType/sign``), and the app's own System categories, such as Starting
    /// balance, add.
    var sign: Int {
        if let kind = LoanOrDebtKind(lockedRole) { return kind.sign }
        if let kind = LoanOrDebtKind(paymentRole: lockedRole) { return kind.paymentSign }
        return type.sign ?? 1
    }
}

nonisolated extension CategoryType {
    /// How money filed under a category of this type moves its wallet, when the type alone says: an Expense takes it
    /// out (`-1`), an Income brings it in (`1`). `nil` for Debt/Loan, where the category's role decides, and System.
    var sign: Int? {
        switch self {
        case .expense: -1
        case .income: 1
        case .debtLoan, .system: nil
        }
    }
}
