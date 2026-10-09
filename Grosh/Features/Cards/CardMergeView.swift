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
            emptyDescription: String(localized: "A Card merges into another unarchived Card paid from the same wallet."),
            row: { CardRow(card: $0) },
            merge: { try source.merge(into: $0, in: context) },
            onMerged: onMerged
        )
    }

    private func consequences(into target: Card?) -> String {
        let destination = target.map { "“\($0.name)”" } ?? String(localized: "the Card you pick")
        let transactions = source.transactions?.count ?? 0
        let text = transactions == 1
            ? String(localized: "Its transaction moves to \(destination)")
            : String(localized: "Its \(transactions) transactions move to \(destination)")
        return text + String(localized: ". Then “\(source.name)” is removed.")
    }
}
