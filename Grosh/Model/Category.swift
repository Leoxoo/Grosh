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

    var parent: Category?

    @Relationship(deleteRule: .nullify, inverse: \Category.parent)
    var children: [Category]? = []

    @Relationship(deleteRule: .nullify, inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    init(
        name: String,
        type: CategoryType,
        symbolName: String,
        color: PaletteColor,
        lockedRole: LockedRole? = nil,
        parent: Category? = nil,
        sortOrder: Int = 0
    ) {
        self.name = name
        self.typeRaw = type.rawValue
        self.symbolName = symbolName
        self.colorName = color.rawValue
        self.lockedRoleRaw = lockedRole?.rawValue
        self.parent = parent
        self.sortOrder = sortOrder
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
        get { PaletteColor(rawValue: colorName) ?? .gray }
        set { colorName = newValue.rawValue }
    }
}
