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
        let transactionCount = (source.transactions ?? []).notDeleted.count
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
