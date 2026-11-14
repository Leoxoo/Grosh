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
    /// Only transactions of at least this many cents, as entered (positive, whatever the type), in whichever currency
    /// each transaction's wallet is in.
    var minimumCents: Int?
    /// Only transactions of at most this many cents, as entered (positive, whatever the type), in whichever currency
    /// each transaction's wallet is in.
    var maximumCents: Int?
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
            && lhs.minimumCents == rhs.minimumCents
            && lhs.maximumCents == rhs.maximumCents
            && lhs.excludedOnly == rhs.excludedOnly
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
                    || transaction.card?.name.localizedStandardContains(query) == true
                    || amount?.matches(cents: transaction.amountCents) == true)
        }
    }

    /// Whether `transaction` passes every filter that is set, search text aside.
    private func passesFilters(_ transaction: Transaction) -> Bool {
        guard dateRange.contains(transaction.day) else { return false }
        if excludedOnly, !transaction.isExcludedFromReport { return false }
        let enteredCents = abs(transaction.amountCents)
        if let minimumCents, enteredCents < minimumCents { return false }
        if let maximumCents, enteredCents > maximumCents { return false }
        if let wallet, transaction.wallet !== wallet { return false }
        if let category, transaction.category !== category, transaction.category?.parent !== category { return false }
        if let card, transaction.card !== card { return false }
        if let type, transaction.category?.type != type { return false }
        return true
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasFilters: Bool {
        var filters = self
        filters.searchText = ""
        return filters != TransactionFilter()
    }

    /// Search text or any filter set.
    var isOn: Bool { isSearching || hasFilters }

    mutating func clearFilters() {
        self = TransactionFilter(searchText: searchText)
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
