/// What a transaction list shows for a wallet selection and a ``TransactionFilter``: the transactions it lists, which
/// amount every row, day and category shows and the total over them adds up (``ListedAmount``), and whether the rows
/// come from more than one wallet. The Transactions tab's list, its search and Search all list through it, so the
/// rows, the day totals and the total of what matches always count the same way.
struct TransactionListing {
    /// The wallet or Total the list shows: the wallet filter's wallet when one is set, otherwise the one selected.
    let selection: WalletSelection
    /// The ledger entries of `selection`'s transactions over all time, before the period and the other filters narrow
    /// them: what the period strip reaches back through and the Opening and Ending balances add up. Search, which has
    /// neither, has none.
    let selected: [LedgerEntry]
    /// What the list shows, in no particular order.
    let transactions: [Transaction]
    /// What each row, day and category shows and the total adds up: what the Card was charged with a Card filter on,
    /// so the total is the Card's to check against the bank's app; in the Total's period, where the money paid back
    /// into other wallets is left out, each Expense's net less it (ADR-0010); otherwise each one's net.
    let listed: ListedAmount
    /// Whether the rows come from more than one wallet, so each shows its wallet's icon: in the Total, or while
    /// searching, which looks across every wallet, unless the wallet filter keeps them to one.
    let mixesWallets: Bool

    /// What the listed transactions come to, as ``listed``: the total a searched or filtered list shows.
    var total: Money { transactions.total(listed) }

    /// The Transactions tab's list of `selection` on `days`, the period shown, from `all` (every transaction outside
    /// Recently Deleted) and `ledger`, their ledger entries. Searching looks across all time and every wallet,
    /// archived ones included, and finds the money paid back into other wallets too; otherwise the list holds the
    /// matching ones among the selection's transactions in the period, the Total leaving out those paybacks, as each
    /// Expense shows them in its net (ADR-0010).
    init(
        _ all: [Transaction], ledger: [LedgerEntry], showing selection: WalletSelection, on days: DayRange,
        filter: TransactionFilter
    ) {
        let shown = filter.selection(replacing: selection)
        let selected = filter.transactions(in: selection, from: ledger)
        if filter.isSearching {
            self.init(searching: all, filter: filter, selection: shown, selected: selected)
            return
        }
        let inDays = selected.filter { days.contains(CalendarDay(rawValue: $0.dayRaw)) }.map(\.transaction)
        let hidesPaybacks = shown == .total
        self.init(
            selection: shown, selected: selected,
            transactions: (hidesPaybacks ? inDays.filter { !$0.isHiddenInTotal } : inDays).matching(filter),
            listed: Self.listed(filter, hidesPaybacks: hidesPaybacks), mixesWallets: shown == .total
        )
    }

    /// Search's list from `all`, every transaction outside Recently Deleted: all time and every wallet, archived
    /// ones included, narrowed by the search text and the filters. It lists nothing until one of them is on.
    static func search(_ all: [Transaction], filter: TransactionFilter) -> TransactionListing {
        TransactionListing(
            searching: filter.isOn ? all : [], filter: filter, selection: filter.selection(replacing: .total),
            selected: []
        )
    }

    private init(
        searching all: [Transaction], filter: TransactionFilter, selection: WalletSelection, selected: [LedgerEntry]
    ) {
        self.init(
            selection: selection, selected: selected,
            transactions: all.isEmpty ? [] : Signpost.interval("Search") { all.matching(filter) },
            listed: Self.listed(filter, hidesPaybacks: false), mixesWallets: filter.wallet == nil
        )
    }

    private init(
        selection: WalletSelection, selected: [LedgerEntry], transactions: [Transaction], listed: ListedAmount,
        mixesWallets: Bool
    ) {
        self.selection = selection
        self.selected = selected
        self.transactions = transactions
        self.listed = listed
        self.mixesWallets = mixesWallets
    }

    private static func listed(_ filter: TransactionFilter, hidesPaybacks: Bool) -> ListedAmount {
        if filter.card != nil { .charged } else if hidesPaybacks { .netInTotal } else { .net }
    }
}
