import Foundation
import SwiftData

nonisolated enum CategoryType: String, CaseIterable, Sendable {
    case expense, income, debtLoan
    /// Categories only the app itself files transactions under, such as Starting balance. Never offered in a picker.
    case system
}

/// What a locked category does for the app. A category with a role can't be deleted or merged.
nonisolated enum LockedRole: String, CaseIterable, Sendable {
    case outgoingTransfer, incomingTransfer
    case otherIncome, otherExpense
    case startingBalance
    case loan, debt, debtCollection, repayment
}

/// What a transaction was for. Categories nest at most two levels deep.
@Model
final class Category {
    var name: String = ""
    var typeRaw: String = CategoryType.expense.rawValue
    var symbolName: String = "questionmark"
    var colorName: String = PaletteColor.gray.rawValue
    var isHidden: Bool = false
    var lockedRoleRaw: String?
    var sortOrder: Int = 0
    /// The ``RecurringKind`` the user set, or `nil` while the category has none of its own. See ``defaultKind``.
    var ownKindRaw: String?

    var parent: Category?

    @Relationship(deleteRule: .nullify, inverse: \Category.parent)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringTransaction.category)
    var recurringTransactions: [RecurringTransaction]? = []

    /// The forgiven Loans and Debts whose forgiven amount counts under this category in reports.
    @Relationship(deleteRule: .nullify, inverse: \Transaction.forgivenCategory)
    var forgivenTransactions: [Transaction]? = []

    init(
        name: String,
        type: CategoryType,
        symbolName: String,
        color: PaletteColor,
        lockedRole: LockedRole? = nil,
        parent: Category? = nil,
        sortOrder: Int = 0,
        ownKind: RecurringKind? = nil
    ) {
        self.name = name
        self.typeRaw = type.rawValue
        self.symbolName = symbolName
        self.color = color
        self.lockedRoleRaw = lockedRole?.rawValue
        self.parent = parent
        self.sortOrder = sortOrder
        self.ownKind = ownKind
    }

    var type: CategoryType {
        get { CategoryType(rawValue: typeRaw) ?? .expense }
        set { typeRaw = newValue.rawValue }
    }

    var lockedRole: LockedRole? {
        get { lockedRoleRaw.flatMap(LockedRole.init(rawValue:)) }
        set { lockedRoleRaw = newValue?.rawValue }
    }

    var isLocked: Bool { lockedRole != nil }

    var color: PaletteColor {
        get { PaletteColor(storedName: colorName) }
        set { colorName = newValue.rawValue }
    }

    var ownKind: RecurringKind? {
        get { ownKindRaw.flatMap(RecurringKind.init(rawValue:)) }
        set { ownKindRaw = newValue?.rawValue }
    }

    /// The Kind a Recurring transaction in this category starts as: its own, else its parent's, else Regular. So a
    /// subcategory with no Kind of its own follows its parent when the parent's changes.
    var defaultKind: RecurringKind {
        ownKind ?? parent?.defaultKind ?? .regular
    }
}
