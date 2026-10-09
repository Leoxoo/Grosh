import SwiftUI

/// The Transactions tab's "…" menu: actions that start from the wallet the tab is showing.
struct TransactionsMenu: View {
    /// The wallet the tab is showing, for actions that start from it.
    let walletSelection: WalletSelection

    @State private var isTransferring = false
    @State private var isAdjustingBalance = false

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Section {
                Button("Transfer", systemImage: "arrow.left.arrow.right") { isTransferring = true }
            }

            Section {
                Button("Adjust Balance", systemImage: "plusminus") { isAdjustingBalance = true }
            }
        }
        .sheet(isPresented: $isTransferring) {
            TransferEditor(viewedWallet: selectedWallet)
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
