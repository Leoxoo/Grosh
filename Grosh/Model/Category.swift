import Foundation
import SwiftData

/// Decides whether a transaction's amount adds to or subtracts from its wallet.
nonisolated enum CategoryType: String, Codable, Sendable {
    case expense
    case income
    case debtLoan
    /// Categories only the app itself files transactions under, such as Starting balance.
    case system
}

/// What the app relies on a locked category for. The app finds these categories by role, never by name.
nonisolated enum CategoryRole: String, Codable, CaseIterable, Sendable {
    case outgoingTransfer
    case incomingTransfer
    case otherIncome
    case otherExpense
    case startingBalance
    case loan
    case debt
    case debtCollection
    case repayment
}

/// What a transaction was for. Categories nest at most two levels deep.
@Model
final class Category {
    var name: String = ""
    var typeValue: String = CategoryType.expense.rawValue
    var iconName: String = "questionmark"
    var colorName: String = "gray"
    var isHidden: Bool = false
    var roleValue: String?
    var sortOrder: Int = 0

    var parent: Category?

    @Relationship(inverse: \Category.parent)
    var children: [Category]? = []

    @Relationship(inverse: \Transaction.category)
    var transactions: [Transaction]? = []

    init(name: String, type: CategoryType, iconName: String, colorName: String, role: CategoryRole? = nil, sortOrder: Int = 0) {
        self.name = name
        self.typeValue = type.rawValue
        self.iconName = iconName
        self.colorName = colorName
        self.roleValue = role?.rawValue
        self.sortOrder = sortOrder
    }

    var type: CategoryType {
        get { CategoryType(rawValue: typeValue) ?? .expense }
        set { typeValue = newValue.rawValue }
    }

    var role: CategoryRole? {
        get { roleValue.flatMap(CategoryRole.init(rawValue:)) }
        set { roleValue = newValue?.rawValue }
    }

    /// A category the app itself depends on: it can't be deleted or merged.
    var isLocked: Bool { role != nil }
}
