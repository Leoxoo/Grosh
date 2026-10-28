import SwiftData
import SwiftUI

/// Picks the category to merge `source` into, then moves its transactions (and subcategories) there and removes it.
struct CategoryMergeView: View {
    let source: Category
    /// Called after the merge, once `source` no longer exists.
    var onMerged: () -> Void = {}

    @Environment(\.modelContext) private var context

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    var body: some View {
        MergeSheet(
            sourceName: source.name,
            targets: Log.store.attempt("Reading the categories to merge into") {
                try catalog.mergeTargets(for: source)
            } ?? [],
            targetName: \.name,
            consequences: consequences(into:),
            emptyDescription: String(localized: Strings.Categories.nothingToMergeInto(source.type.title)),
            row: { CategoryLabel(category: $0) },
            merge: { try catalog.merge(source, into: $0) },
            onMerged: onMerged
        )
    }

    private func consequences(into target: Category?) -> String {
        let destination = target.map { "“\($0.name)”" } ?? String(localized: Strings.Categories.theCategoryYouPick)
        let transactions = (source.transactions ?? []).notDeleted.count
        let subcategories = source.children?.count ?? 0
        var text = transactions == 1
            ? String(localized: Strings.Merge.itsTransactionMovesTo(destination))
            : String(localized: Strings.Merge.itsTransactionsMoveTo(transactions, destination))
        if subcategories > 0 {
            text += String(localized: Strings.Categories.subcategoriesMoveUnder(subcategories))
        }
        return text + String(localized: Strings.Merge.thenRemoved(source.name))
    }
}
