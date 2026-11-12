import Foundation
import SwiftData

/// What merging a Card or a category into another does, as the merge sheet's footer says it: "Its 3 transactions move
/// to “Groceries”, its 2 subcategories move under it. Then “Food” is removed."
nonisolated enum MergeConsequences {
    /// `sourceName` is what is merged away, with `transactionCount` transactions outside Recently Deleted and
    /// `subcategoryCount` subcategories; `targetName` is what it merges into, or `nil` before one is chosen, which
    /// `unchosen` ("the Card you pick") stands for.
    static func text(
        sourceName: String, transactionCount: Int, subcategoryCount: Int = 0, targetName: String?, unchosen: String
    ) -> String {
        let destination = targetName.map { String(localized: Strings.Merge.quoted($0)) } ?? unchosen
        switch (transactionCount, subcategoryCount) {
        case (1, 0):
            return String(localized: Strings.Merge.itsTransactionMovesTo(destination, thenRemoved: sourceName))
        case (_, 0):
            return String(localized: Strings.Merge.itsTransactionsMoveTo(transactionCount, destination, thenRemoved: sourceName))
        case (1, _):
            return String(localized: Strings.Merge.itsTransactionAndSubcategoriesMoveTo(
                destination, subcategories: subcategoryCount, thenRemoved: sourceName
            ))
        default:
            return String(localized: Strings.Merge.itsTransactionsAndSubcategoriesMoveTo(
                transactionCount, destination, subcategories: subcategoryCount, thenRemoved: sourceName
            ))
        }
    }
}

extension Card {
    /// The transactions paid with the Card outside Recently Deleted, the ones the merge sheet says move: for
    /// `fetchCount`, which counts them in the store rather than loading the thousands a main Card pays for.
    var notDeletedTransactions: FetchDescriptor<Transaction> {
        let id = persistentModelID
        return FetchDescriptor(predicate: #Predicate { $0.card?.persistentModelID == id && $0.deletedAt == nil })
    }
}

extension Category {
    /// The transactions filed under the category itself outside Recently Deleted, the ones the merge sheet says move:
    /// for `fetchCount`, which counts them in the store rather than loading them.
    var notDeletedTransactions: FetchDescriptor<Transaction> {
        let id = persistentModelID
        return FetchDescriptor(predicate: #Predicate { $0.category?.persistentModelID == id && $0.deletedAt == nil })
    }

    /// What deleting the category takes with it, as the confirmation says: its subcategories, or that it can't be
    /// undone.
    var deleteMessage: String {
        let subcategories = children?.count ?? 0
        return subcategories == 0
            ? String(localized: Strings.Common.cantBeUndone)
            : String(localized: Strings.Categories.subcategoriesDeletedToo(subcategories))
    }
}
