import Foundation
import SwiftData

/// What a transaction list is narrowed to: search text and filters. Everything left empty matches every
/// transaction.
nonisolated struct TransactionFilter: Equatable {
    /// Finds the text in a transaction's note, its category's name or the name of any of the people in its With,
    /// ignoring case and accents. A number also finds amounts: `973` finds $973.17.
    var searchText = ""
    /// Only this wallet's transactions, in place of the wallet or Total the list is showing. Any wallet, archived
    /// ones and those left out of the Total included.
    var wallet: Wallet?
    /// Only transactions filed under this category or, for a parent, under any of its subcategories.
    var category: Category?
    /// Only transactions paid with this Card.
    var card: Card?
    /// Only transactions with this Person among the people in With, whoever else is there (ADR-0009). Hidden people
    /// can be chosen: Hide keeps their history.
    var person: Person?
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

    /// Wallets, categories, Cards and people are compared by identity, so this doesn't rely on their Equatable
    /// conformance.
    static func == (lhs: TransactionFilter, rhs: TransactionFilter) -> Bool {
        lhs.searchText == rhs.searchText
            && lhs.wallet === rhs.wallet
            && lhs.category === rhs.category
            && lhs.card === rhs.card
            && lhs.person === rhs.person
            && lhs.type == rhs.type
            && lhs.dateRange == rhs.dateRange
            && lhs.minimumAmount == rhs.minimumAmount
            && lhs.maximumAmount == rhs.maximumAmount
            && lhs.excludedOnly == rhs.excludedOnly
    }

    /// Whether `transaction` passes the search and every filter that is set.
    func matches(_ transaction: Transaction) -> Bool {
        Search(self).matches(transaction)
    }

    /// The search text trimmed and read as an amount once, for checking many transactions against the filter.
    fileprivate struct Search {
        let filter: TransactionFilter
        let query: String
        let amount: AmountQuery?
        /// The transactions the filter's Person is in With on, read once from the Person rather than from each
        /// transaction's people, or `nil` with no Person filter.
        let withPerson: Set<PersistentIdentifier>?

        init(_ filter: TransactionFilter) {
            self.filter = filter
            withPerson = filter.person.map { Set(($0.transactions ?? []).map(\.persistentModelID)) }
            query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            amount = query.isEmpty ? nil : AmountQuery(query)
        }

        func matches(_ transaction: Transaction) -> Bool {
            filter.passesFilters(transaction)
                && withPerson?.contains(transaction.persistentModelID) != false
                && (query.isEmpty
                    || transaction.note.localizedStandardContains(query)
                    || transaction.withName.localizedStandardContains(query)
                    || transaction.category?.name.localizedStandardContains(query) == true
                    || amount?.matches(Money(cents: transaction.amountCents)) == true)
        }
    }

    /// Whether `transaction` passes every filter that is set, search text aside.
    private func passesFilters(_ transaction: Transaction) -> Bool {
        guard dateRange.contains(transaction.day) else { return false }
        if excludedOnly, !transaction.isExcludedFromReport { return false }
        let enteredCents = abs(transaction.amountCents)
        if let minimumAmount, enteredCents < minimumAmount.cents { return false }
        if let maximumAmount, enteredCents > maximumAmount.cents { return false }
        if let wallet, transaction.wallet !== wallet { return false }
        if let category, transaction.category !== category, transaction.category?.parent !== category { return false }
        if let card, transaction.card !== card { return false }
        if let type, transaction.category?.type != type { return false }
        return true
    }

    /// The total a list of `transactions` shows: their net total, or with a Card filter on the Card's total, which counts
    /// what the Card was charged (``Sequence/charged``) rather than the net.
    func total(of transactions: [Transaction]) -> Money {
        card == nil ? transactions.net : transactions.charged
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

    /// Resets every filter, leaving the search text.
    mutating func clearFilters() {
        self = TransactionFilter(searchText: searchText)
    }

    /// The transactions the Transactions tab lists from `all`. Searching looks across all time and every wallet,
    /// archived ones included; otherwise the list holds the matching ones among ``transactions(in:from:)`` on `days`
    /// (the selected period).
    func listed(from all: [Transaction], selection: WalletSelection, on days: DayRange) -> [Transaction] {
        listed(
            from: all, selected: transactions(in: selection, from: all.map(LedgerEntry.init)), on: days,
            hidingPaybacksIn: self.selection(replacing: selection)
        )
    }

    /// ``listed(from:selection:on:)`` with the selection's transactions at hand already: `selected`, as
    /// ``transactions(in:from:)`` picks them from the ledger entries of `all`. In the Total (`hidingPaybacksIn`) the
    /// money paid back into another wallet is left out, as its Expense shows it in its net (ADR-0010); searching still
    /// finds it.
    func listed(
        from all: [Transaction], selected: [LedgerEntry], on days: DayRange,
        hidingPaybacksIn selection: WalletSelection? = nil
    ) -> [Transaction] {
        if isSearching { return Signpost.interval("Search") { all.matching(self) } }
        let inDays = selected.filter { days.contains(CalendarDay(rawValue: $0.dayRaw)) }.map(\.transaction)
        let shown = selection == WalletSelection.total ? inDays.filter { !$0.isHiddenInTotal } : inDays
        return shown.matching(self)
    }

    /// What the list shows: the wallet filter's wallet when one is set, otherwise `selection`.
    func selection(replacing selection: WalletSelection) -> WalletSelection {
        wallet.map(WalletSelection.wallet) ?? selection
    }

    /// The transactions the Transactions tab steps through period by period, before the period and the other filters
    /// narrow them: the wallet filter's wallet when one is set (any wallet, archived or left out of the Total, in
    /// place of `selection`), otherwise `selection`'s. The period strip reaches back to the first of them.
    func transactions<Entry: DatedAmount>(in selection: WalletSelection, from all: [Entry]) -> [Entry] {
        let selection = self.selection(replacing: selection)
        // A wallet is asked once whether it belongs, rather than once for each of its transactions.
        var includesWallet: [ObjectIdentifier?: Bool] = [:]
        return all.filter { transaction in
            let wallet = transaction.wallet
            let key = wallet.map(ObjectIdentifier.init)
            if let known = includesWallet[key] { return known }
            let includes = selection.includesWallet(wallet)
            includesWallet[key] = includes
            return includes
        }
    }
}

nonisolated extension Sequence where Element == Transaction {
    /// The transactions that pass `filter`.
    func matching(_ filter: TransactionFilter) -> [Transaction] {
        let search = TransactionFilter.Search(filter)
        return self.filter(search.matches)
    }
}
