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
        let transactionCount = (source.transactions ?? []).notDeleted.count
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
