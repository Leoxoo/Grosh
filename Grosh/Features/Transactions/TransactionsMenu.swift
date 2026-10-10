import SwiftUI

/// The Transactions tab's "…" menu: actions that start from the wallet the tab is showing.
struct TransactionsMenu: View {
    /// What the tab is showing: one wallet or the Total.
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
            TransferEditor(viewedWallet: viewedWallet)
        }
        .sheet(isPresented: $isAdjustingBalance) {
            AdjustBalanceEditor(viewedWallet: viewedWallet)
        }
    }

    /// The one wallet the tab is showing, or `nil` for the Total.
    private var viewedWallet: Wallet? {
        if case .wallet(let wallet) = walletSelection { wallet } else { nil }
    }
}
