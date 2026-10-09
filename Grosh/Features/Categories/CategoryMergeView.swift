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
            targets: (try? catalog.mergeTargets(for: source)) ?? [],
            targetName: \.name,
            consequences: consequences(into:),
            emptyDescription: String(localized: "There's no other \(source.type.title) category this one can be merged into."),
            row: { CategoryLabel(category: $0) },
            merge: { try catalog.merge(source, into: $0) },
            onMerged: onMerged
        )
    }

    private func consequences(into target: Category?) -> String {
        let destination = target.map { "“\($0.name)”" } ?? String(localized: "the category you pick")
        let transactions = source.transactions?.count ?? 0
        let subcategories = source.children?.count ?? 0
        var text = transactions == 1
            ? String(localized: "Its transaction moves to \(destination)")
            : String(localized: "Its \(transactions) transactions move to \(destination)")
        if subcategories > 0 {
            text += String(localized: " and its \(subcategories) subcategories move under it")
        }
        return text + String(localized: ". Then “\(source.name)” is removed.")
    }
}
