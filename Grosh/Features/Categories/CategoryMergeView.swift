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
        // Counted in the store once, when the sheet opens.
        MadeOnce {
            Log.store.attempt("Counting a category's transactions") {
                try context.fetchCount(source.notDeletedTransactions)
            } ?? 0
        } content: { transactionCount in
            mergeSheet(transactionCount: transactionCount)
        }
    }

    private func mergeSheet(transactionCount: Int) -> some View {
        MergeSheet(
            sourceName: source.name,
            targets: Log.store.attempt("Reading the categories to merge into") {
                try catalog.mergeTargets(for: source)
            } ?? [],
            targetName: \.name,
            consequences: { target in
                MergeConsequences.text(
                    sourceName: source.name, transactionCount: transactionCount,
                    subcategoryCount: source.children?.count ?? 0, targetName: target?.name,
                    unchosen: String(localized: Strings.Categories.theCategoryYouPick)
                )
            },
            emptyDescription: String(localized: Strings.Categories.nothingToMergeInto(source.type.title)),
            row: { CategoryLabel(category: $0) },
            merge: { try catalog.merge(source, into: $0) },
            onMerged: onMerged
        )
    }
}
