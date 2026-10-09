/// Whose transactions a list shows: the Total (every wallet counted in it) or one wallet.
enum WalletSelection: Hashable {
    case total
    case wallet(Wallet)

    /// Whether `transaction` belongs to the selection. The Total holds the transactions of unarchived wallets
    /// marked "Include in total", the same wallets its balance adds up.
    func includes(_ transaction: Transaction) -> Bool {
        switch self {
        case .total: transaction.wallet?.countsInTotal ?? false
        case .wallet(let wallet): transaction.wallet == wallet
        }
    }

    /// The selection's balance on `today`: the Total of `wallets`, or the one wallet's balance.
    func balance(asOf today: CalendarDay, wallets: [Wallet]) -> Money {
        switch self {
        case .total: Wallet.total(of: wallets, asOf: today)
        case .wallet(let wallet): wallet.balance(asOf: today)
        }
    }
}
