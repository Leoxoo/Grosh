import Foundation

/// Why ``CategoryCatalog`` refused a change.
nonisolated enum CategoryError: Error, Equatable {
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

extension CategoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .locked: "The app relies on this category. Only its icon can be changed."
        case .differentType: "Pick a category of the same type."
        case .sameCategory: "Pick a different category."
        case .tooDeep: "Categories nest at most two levels deep."
        case .hasTransactions: "This category has transactions. Merge it into another category instead."
        case .nameRequired: "Enter a name."
        case .nameTaken: "Another category of this type already has this name."
        case .fixedType: "Only Expense and Income categories can be added or moved."
        }
    }
}
