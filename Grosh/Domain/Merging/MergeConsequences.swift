import Foundation

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
        var text = transactionCount == 1
            ? String(localized: Strings.Merge.itsTransactionMovesTo(destination))
            : String(localized: Strings.Merge.itsTransactionsMoveTo(transactionCount, destination))
        if subcategoryCount > 0 {
            text += String(localized: Strings.Categories.subcategoriesMoveUnder(subcategoryCount))
        }
        return text + String(localized: Strings.Merge.thenRemoved(sourceName))
    }
}

extension Category {
    /// What deleting the category takes with it, as the confirmation says: its subcategories, or that it can't be
    /// undone.
    var deleteMessage: String {
        let subcategories = children?.count ?? 0
        return subcategories == 0
            ? String(localized: Strings.Common.cantBeUndone)
            : String(localized: Strings.Categories.subcategoriesDeletedToo(subcategories))
    }
}
