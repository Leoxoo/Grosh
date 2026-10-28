import Foundation

/// Why ``CategoryCatalog`` refused a change.
nonisolated enum CategoryRuleError: Error, Equatable {
    /// Locked categories keep everything but their icon: no delete, merge, rename, retype, move or hide.
    case locked
    /// A category can only be merged into, or nested under, a category of its own type.
    case differentType
    /// A category can't be merged into, or nested under, itself.
    case sameCategory
    /// Categories nest at most two levels deep.
    case tooDeep
    /// The category (or one of its subcategories) has transactions: merge it instead of deleting, and keep its type.
    case hasTransactions
    case nameRequired
    /// Names are unique within a category type, ignoring case.
    case nameTaken
    /// Only Expense and Income categories are the user's own; Debt/Loan and system categories are fixed.
    case fixedType
}

extension CategoryRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .locked: String(localized: Strings.Categories.lockedError)
        case .differentType: String(localized: Strings.Categories.differentType)
        case .sameCategory: String(localized: Strings.Categories.sameCategory)
        case .tooDeep: String(localized: Strings.Categories.tooDeep)
        case .hasTransactions: String(localized: Strings.Categories.hasTransactions)
        case .nameRequired: String(localized: Strings.Categories.nameRequired)
        case .nameTaken: String(localized: Strings.Categories.nameTaken)
        case .fixedType: String(localized: Strings.Categories.fixedType)
        }
    }
}
