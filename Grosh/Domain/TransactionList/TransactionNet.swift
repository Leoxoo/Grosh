nonisolated extension Sequence where Element == Transaction {
    /// What the transactions add to or take from the balance together: every one counts, excluded from report or
    /// not, each as its net (``Transaction/netCents``). A day's or a category's total in the list, or what a search or
    /// filter matches. A Card's total is ``charged`` instead.
    var net: Money { added(\.netCents) }

    /// What the Card was charged for the transactions together: their original amounts, Reimbursements not counted, as
    /// on the Card's statement. A Card's statement total, and the Card filter's.
    var charged: Money { added(\.amountCents) }

    /// `cents` of each transaction added up, in the currency of their wallet. A list's transactions share one currency
    /// unless it is the Total of wallets in different currencies, where the sum is labelled with the first one's: only
    /// the balances keep each currency apart (``WalletBalances/total(of:)``).
    fileprivate func added(_ cents: (Transaction) -> Int) -> Money {
        var total = 0
        var currencyCode: String?
        for transaction in self {
            if currencyCode == nil { currencyCode = transaction.amount.currencyCode }
            total += cents(transaction)
        }
        return Money(cents: total, currencyCode: currencyCode ?? Money.defaultCurrencyCode)
    }
}

/// Which amount a list shows for each transaction and adds up: its net, Reimbursements counted, as every list shows it;
/// or what its Card was charged, as a Card's statement shows it, so the statement reconciles with the Card (ADR-0008);
/// or, in the Total, its net less what was paid back into other wallets in the Total, which that list leaves out
/// (ADR-0010).
nonisolated enum ListedAmount: Sendable {
    case net
    case charged
    /// The net the Total shows (``Transaction/totalViewNetCents``).
    case netInTotal
}

extension Sequence where Element == Transaction {
    /// What the transactions come to together, as `listed`: ``net``, ``charged`` or ``netInTotal``.
    func total(_ listed: ListedAmount) -> Money {
        switch listed {
        case .net: net
        case .charged: charged
        case .netInTotal: added(\.totalViewNetCents)
        }
    }
}
