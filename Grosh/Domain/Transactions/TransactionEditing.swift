/// Which editor the transaction detail's Edit opens.
nonisolated enum TransactionEditFlow: Hashable, Sendable {
    /// The Add Transaction sheet, which signs the amount by category. Duplicate is offered too.
    case addSheet
    /// A wallet's Starting balance: its amount (of either sign), date and note. Never duplicated, since a
    /// wallet has one Starting balance.
    case startingBalance
}

extension Transaction {
    /// How the detail edits this transaction, or `nil` when the flow that recorded it owns it: the halves of a
    /// Transfer, a Debt Collection or Repayment from Record payment, and every linked transaction. A Starting
    /// balance has its own editor, since the Add sheet would re-sign its amount by type and never offers its
    /// category.
    var editFlow: TransactionEditFlow? {
        guard linkID == nil else { return nil }
        switch category?.lockedRole {
        case .startingBalance: return .startingBalance
        case .outgoingTransfer, .incomingTransfer, .debtCollection, .repayment: return nil
        case .otherIncome, .otherExpense, .loan, .debt, nil: return .addSheet
        }
    }

    /// Whether the detail offers Duplicate: only for what the Add sheet edits, but never a balance adjustment,
    /// whose copy wouldn't make any balance right.
    var canBeDuplicated: Bool { editFlow == .addSheet && !isBalanceAdjustment }
}
