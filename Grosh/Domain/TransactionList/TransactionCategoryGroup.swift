import SwiftData

/// One category of the transaction list viewed by category: the transactions filed under it and their total.
struct TransactionCategoryGroup: Identifiable {
    /// The category the transactions are filed under, or `nil` for those filed under none.
    let category: Category?
    /// In list order: newest day first, the most recently entered on top within a day.
    let transactions: [Transaction]

    var id: PersistentIdentifier? { category?.persistentModelID }

    /// What the category added to or took from the balance: every transaction counts, excluded from report or
    /// not, so the groups of a period add up to its difference.
    var total: Money {
        Money(cents: transactions.reduce(0) { $0 + $1.amountCents })
    }
}

extension TransactionCategoryGroup {
    /// `transactions` grouped under the category each is filed under (a subcategory is its own group). Money in
    /// comes first, largest first, then spending, largest first.
    static func groups(of transactions: [Transaction]) -> [TransactionCategoryGroup] {
        let byCategory = Dictionary(grouping: transactions.inListOrder()) { $0.category?.persistentModelID }
        return byCategory.values
            .map { TransactionCategoryGroup(category: $0.first?.category, transactions: $0) }
            .sorted { $0.isListed(before: $1) }
    }

    private func isListed(before other: TransactionCategoryGroup) -> Bool {
        let total = total.cents
        let otherTotal = other.total.cents
        if (total < 0) != (otherTotal < 0) { return total >= 0 }
        if total != otherTotal { return abs(total) > abs(otherTotal) }
        // Equal totals: by name, with the transactions filed under no category last.
        if (category == nil) != (other.category == nil) { return other.category == nil }
        return (category?.name ?? "") < (other.category?.name ?? "")
    }
}
