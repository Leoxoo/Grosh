/// Whose transactions a list shows: the Total (every wallet counted in it) or one wallet.
nonisolated enum WalletSelection: Hashable {
    case total
    case wallet(Wallet)

    /// Whether `transaction` belongs to the selection. The Total holds the transactions of unarchived wallets
    /// marked "Include in total", the same wallets its balance adds up.
    func includes(_ transaction: Transaction) -> Bool {
        includesWallet(transaction.wallet)
    }

    /// Whether a transaction or Scheduled row paid from `wallet` belongs to the selection.
    func includesWallet(_ wallet: Wallet?) -> Bool {
        switch self {
        case .total: wallet?.countsInTotal ?? false
        case .wallet(let selected): wallet == selected
        }
    }
}
