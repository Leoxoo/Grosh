import Foundation

/// What a transaction list is narrowed to: search text and filters. Everything left empty matches every
/// transaction.
struct TransactionFilter: Equatable {
    /// Finds the text in a transaction's note or its category's name, ignoring case and accents. A number also
    /// finds amounts: `973` finds $973.17.
    var searchText = ""
    /// Only this wallet's transactions. Any wallet, archived ones included.
    var wallet: Wallet?
    /// Only transactions filed under this category or, for a parent, under any of its subcategories.
    var category: Category?
    /// Only transactions paid with this Card.
    var card: Card?
    /// Only transactions whose category is of this type.
    var type: CategoryType?
    /// Only transactions dated within these days. Open on both sides by default.
    var dateRange = DayRange()
    /// Only transactions of at least this amount, as entered (positive, whatever the type).
    var minimumAmount: Money?
    /// Only transactions of at most this amount, as entered (positive, whatever the type).
    var maximumAmount: Money?
    /// Only transactions excluded from report.
    var excludedOnly = false

    /// Whether `transaction` passes the search and every filter that is set.
    func matches(_ transaction: Transaction) -> Bool {
        guard dateRange.contains(transaction.day) else { return false }
        if excludedOnly, !transaction.isExcludedFromReport { return false }
        let enteredCents = abs(transaction.amountCents)
        if let minimumAmount, enteredCents < minimumAmount.cents { return false }
        if let maximumAmount, enteredCents > maximumAmount.cents { return false }
        if let wallet, transaction.wallet != wallet { return false }
        if let category, transaction.category != category, transaction.category?.parent != category { return false }
        if let card, transaction.card != card { return false }
        if let type, transaction.category?.type != type { return false }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty
            || transaction.note.localizedStandardContains(query)
            || transaction.category?.name.localizedStandardContains(query) == true
            || AmountQuery(query)?.matches(transaction.amount) == true
    }

    /// Whether there is search text to look for.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether any filter is set, search text aside.
    var hasFilters: Bool {
        var filters = self
        filters.searchText = ""
        return filters != TransactionFilter()
    }

    /// Whether the filter narrows anything: search text or any filter set.
    var isOn: Bool { isSearching || hasFilters }

    /// The transactions the Transactions tab lists from `all`. Searching looks across all time and every wallet,
    /// archived ones included; otherwise the list holds `selection`'s transactions on `days` (the selected period).
    func listed(from all: [Transaction], selection: WalletSelection, on days: DayRange) -> [Transaction] {
        if isSearching { return all.matching(self) }
        return all.filter { selection.includes($0) && days.contains($0.day) }.matching(self)
    }
}

extension Sequence where Element == Transaction {
    /// The transactions that pass `filter`.
    func matching(_ filter: TransactionFilter) -> [Transaction] {
        self.filter(filter.matches)
    }

    /// What the transactions add up to, excluded from report or not: with a Card filter on, that Card's total.
    var net: Money {
        Money(cents: reduce(0) { $0 + $1.amountCents })
    }
}
