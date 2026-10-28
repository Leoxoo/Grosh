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
        MergeSheet(
            sourceName: source.name,
            targets: source.mergeTargets,
            targetName: \.name,
            consequences: consequences(into:),
            emptyDescription: String(localized: Strings.Cards.mergeEmpty),
            row: { CardRow(card: $0) },
            merge: { try source.merge(into: $0, in: context) },
            onMerged: onMerged
        )
    }

    private func consequences(into target: Card?) -> String {
        let destination = target.map { "“\($0.name)”" } ?? String(localized: Strings.Cards.theCardYouPick)
        let transactions = (source.transactions ?? []).notDeleted.count
        let text = transactions == 1
            ? String(localized: Strings.Merge.itsTransactionMovesTo(destination))
            : String(localized: Strings.Merge.itsTransactionsMoveTo(transactions, destination))
        return text + String(localized: Strings.Merge.thenRemoved(source.name))
    }
}
