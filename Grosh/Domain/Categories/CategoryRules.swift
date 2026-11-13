import Foundation

extension Category {
    /// Hidden itself, or a subcategory of a hidden parent.
    var isHiddenInTree: Bool { isHidden || parent?.isHidden == true }

    /// Outgoing transfer or Incoming transfer: one half of a Transfer, which never carries a Card.
    var isTransferHalf: Bool { lockedRole == .outgoingTransfer || lockedRole == .incomingTransfer }

    /// `category`'s name, or "Uncategorized" for none.
    static func name(of category: Category?) -> String {
        category?.name ?? String(localized: Strings.Common.uncategorized)
    }
}

extension Transaction {
    /// The category's name, or "Uncategorized" for a transaction filed under none.
    var categoryName: String { Category.name(of: category) }
}

nonisolated extension CategoryType {
    /// The types the user sees, in order: the segments of Account → Categories and of the Add sheet.
    static let segments: [CategoryType] = ordinary + [.debtLoan]

    /// Expense and Income, in order: the types of the user's own categories, and all that a Recurring transaction, a
    /// category's editor, a balance adjustment or a part of a Split offers.
    static let ordinary: [CategoryType] = [.expense, .income]

    /// Expense and Income categories are the user's own; Debt/Loan and system categories are fixed.
    var isUserManaged: Bool { Self.ordinary.contains(self) }
}

extension LockedRole {
    /// Whether the user picks this category by hand. The rest are filed by their own flows: Transfer,
    /// Record payment, and a new wallet's Starting balance.
    var isOfferedInPicker: Bool {
        switch self {
        case .otherIncome, .otherExpense, .loan, .debt: true
        case .outgoingTransfer, .incomingTransfer, .debtCollection, .repayment, .startingBalance, .reimbursement: false
        }
    }
}
