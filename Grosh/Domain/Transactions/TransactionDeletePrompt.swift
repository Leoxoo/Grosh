import Foundation
import SwiftData

/// What the user is asked before deleting one or more transactions: a plain confirmation when no link would break,
/// otherwise whether to delete the related transactions left out too.
struct TransactionDeletePrompt {
    let transactions: [Transaction]
    /// How many transactions are linked to ``transactions`` without being among them.
    let relatedCount: Int
    /// The answers offered, the default first.
    let scopes: [TransactionDeleteScope]

    init(for transactions: [Transaction], in context: ModelContext) throws {
        self.transactions = transactions
        relatedCount = try transactions.related(in: context).count
        scopes = try transactions.deleteScopes(in: context)
    }

    var title: String {
        if relatedCount > 0 { return String(localized: Strings.Transactions.deleteRelatedToo) }
        return transactions.count == 1
            ? String(localized: Strings.Transactions.deleteThisTransaction)
            : String(localized: Strings.Transactions.deleteCountQuestion(transactions.count))
    }

    var message: String? {
        guard relatedCount > 0 else { return nil }
        return transactions.count == 1
            ? String(localized: Strings.Transactions.hasRelated(relatedCount))
            : String(localized: Strings.Transactions.selectedHaveRelated(relatedCount))
    }

    func buttonTitle(for scope: TransactionDeleteScope) -> String {
        scope.buttonTitle(selectedCount: transactions.count, relatedCount: relatedCount)
    }
}

extension TransactionDeleteScope {
    /// The button that picks this answer when deleting `selectedCount` transactions that have `relatedCount`
    /// related transactions left out of them.
    func buttonTitle(selectedCount: Int, relatedCount: Int) -> String {
        switch self {
        case .onlySelected where selectedCount == 1:
            relatedCount > 0 ? String(localized: Strings.Common.onlyThisOne) : String(localized: Strings.Transactions.deleteTransaction)
        case .onlySelected:
            relatedCount > 0
                ? String(localized: Strings.Transactions.onlyThese(selectedCount))
                : String(localized: Strings.Transactions.deleteCount(selectedCount))
        case .withRelated:
            selectedCount + relatedCount == 2
                ? String(localized: Strings.Transactions.deleteBoth)
                : String(localized: Strings.Transactions.deleteAll(selectedCount + relatedCount))
        }
    }
}
