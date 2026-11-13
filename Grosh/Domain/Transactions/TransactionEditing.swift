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
    /// or Repayment from Record payment, what a Loan or Debt writes off beside one, and a payback into another wallet
    /// (ADR-0010). The link's kind says which (ADR-0012).
    /// A Loan or Debt stays with the Add sheet once it has payments (which share its link), with its wallet and category
    /// locked (``TransactionDraft/isLockedByPayments``), and so does an Expense paid back into another wallet. A part of
    /// a Split (``isSplitPart``) is edited there too, on its own. A Starting balance and a transfer half have their own
    /// editors, since the Add sheet would re-sign their amount by type and never offers their category.
    var editFlow: TransactionEditFlow? {
        switch category?.lockedRole {
        case .outgoingTransfer, .incomingTransfer: return .transferHalf
        case .loan, .debt: return .addSheet
        case .debtCollection, .repayment, .reimbursement: return nil
        case .startingBalance, .otherIncome, .otherExpense, nil:
            if linkKind == .transfer || linkKind == .loanOrDebt { return nil }
            return category?.lockedRole == .startingBalance ? .startingBalance : .addSheet
        }
    }

    /// Whether the detail offers Duplicate: only for what the Add sheet edits, but never a balance adjustment,
    /// whose copy wouldn't make any balance right.
    var canBeDuplicated: Bool { editFlow == .addSheet && !isBalanceAdjustment }
}
