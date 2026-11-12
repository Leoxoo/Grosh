/// Whose transactions a list shows: the Total (every wallet counted in it) or one wallet.
nonisolated enum WalletSelection: Hashable {
    case total
    case wallet(Wallet)

    /// Whether `transaction` belongs to the selection. The Total holds the transactions of unarchived wallets
    /// marked "Include in total", the same wallets its balance adds up.
    func includes(_ transaction: Transaction) -> Bool {
        includesWallet(transaction.wallet)
    }

    /// The currency the selection's figures are written in: the wallet's own, or for the Total that of the first wallet
    /// counted in it (``Wallet/countsInTotal``) in `wallets`' order, the user's, or the default one while none is. The
    /// Total's balance keeps each currency apart (``WalletBalances/total(of:)``); a figure that adds up what counts,
    /// such as the Report's and the Month graph's, is one number, so wallets in another currency are added in as they
    /// are and the figure is labelled with this one.
    func currencyCode(among wallets: [Wallet]) -> String {
        switch self {
        case .total: wallets.first(where: \.countsInTotal).currencyCodeOrDefault
        case .wallet(let wallet): wallet.currencyCode
        }
    }

    /// Whether a transaction or Scheduled row paid from `wallet` belongs to the selection.
    func includesWallet(_ wallet: Wallet?) -> Bool {
        switch self {
        case .total: wallet?.countsInTotal ?? false
        case .wallet(let selected): wallet == selected
        }
    }
}
