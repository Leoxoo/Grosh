/// Which editor the transaction detail's Edit opens.
nonisolated enum TransactionEditFlow: Hashable, Sendable {
    /// The Add Transaction sheet, which signs the amount by category. Duplicate is offered too.
    case addSheet
    /// A wallet's Starting balance: its amount (of either sign), date and note. Never duplicated, since a
    /// wallet has one Starting balance.
    case startingBalance
    /// One half of a Transfer: its amount, date and note. A change to the amount or date offers to update the
    /// other half too. Never duplicated, since a half on its own isn't a transfer.
    case transferHalf
}

extension Transaction {
    /// How the detail edits this transaction, or `nil` when the flow that recorded it owns it: a Debt Collection
    /// or Repayment from Record payment, and every other linked transaction. A Starting balance and a transfer
    /// half have their own editors, since the Add sheet would re-sign their amount by type and never offers
    /// their category.
    var editFlow: TransactionEditFlow? {
        if category?.isTransferHalf == true { return .transferHalf }
        guard linkID == nil else { return nil }
        switch category?.lockedRole {
        case .startingBalance: return .startingBalance
        case .outgoingTransfer, .incomingTransfer, .debtCollection, .repayment: return nil
        case .otherIncome, .otherExpense, .loan, .debt, nil: return .addSheet
        }
    }

    /// Whether the detail offers Duplicate: only for what the Add sheet edits.
    var canBeDuplicated: Bool { editFlow == .addSheet }
}
