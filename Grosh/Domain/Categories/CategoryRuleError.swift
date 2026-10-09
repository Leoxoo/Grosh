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
        case .locked: String(localized: "The app relies on this category. Only its icon can be changed.")
        case .differentType: String(localized: "Pick a category of the same type.")
        case .sameCategory: String(localized: "Pick a different category.")
        case .tooDeep: String(localized: "Categories nest at most two levels deep.")
        case .hasTransactions: String(localized: "This category has transactions. Merge it into another category instead.")
        case .nameRequired: String(localized: "Enter a name.")
        case .nameTaken: String(localized: "Another category of this type already has this name.")
        case .fixedType: String(localized: "Only Expense and Income categories can be added or moved.")
        }
    }
}
