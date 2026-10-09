import SwiftUI

/// The Transactions tab's "…" menu: actions that start from the wallet the tab is showing.
struct TransactionsMenu: View {
    /// The wallet the tab is showing, for actions that start from it.
    let walletSelection: WalletSelection

    @State private var isAdjustingBalance = false

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Section {
                Button("Adjust Balance", systemImage: "plusminus") { isAdjustingBalance = true }
            }
        }
        .sheet(isPresented: $isAdjustingBalance) {
            AdjustBalanceEditor(wallet: selectedWallet)
        }
    }

    /// The one wallet the tab is showing, or `nil` for the Total.
    private var selectedWallet: Wallet? {
        if case .wallet(let wallet) = walletSelection { wallet } else { nil }
    }
}
