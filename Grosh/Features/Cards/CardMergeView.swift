import SwiftData
import SwiftUI

/// Merges one Card into another paid from the same wallet: every transaction paid with `source` moves to the
/// chosen Card, then `source` is removed.
struct CardMergeView: View {
    let source: Card
    /// Called after the merge, once `source` no longer exists.
    var onMerged: () -> Void = {}

    @Environment(\.modelContext) private var context

    var body: some View {
        // Counted in the store once, when the sheet opens.
        MadeOnce {
            Log.store.attempt("Counting a Card's transactions") {
                try context.fetchCount(source.notDeletedTransactions)
            } ?? 0
        } content: { transactionCount in
            mergeSheet(transactionCount: transactionCount)
        }
    }

    private func mergeSheet(transactionCount: Int) -> some View {
        MergeSheet(
            sourceName: source.name,
            targets: source.mergeTargets,
            targetName: \.name,
            consequences: { target in
                MergeConsequences.text(
                    sourceName: source.name, transactionCount: transactionCount, targetName: target?.name,
                    unchosen: String(localized: Strings.Cards.theCardYouPick)
                )
            },
            emptyDescription: String(localized: Strings.Cards.mergeEmpty),
            row: { CardRow(card: $0) },
            merge: { try source.merge(into: $0, in: context) },
            onMerged: onMerged
        )
    }
}
