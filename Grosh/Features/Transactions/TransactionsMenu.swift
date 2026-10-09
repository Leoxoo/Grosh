import SwiftUI

/// The Transactions tab's "…" menu: making a Transfer.
struct TransactionsMenu: View {
    /// The wallet the tab is showing, for actions that start from it.
    let walletSelection: WalletSelection

    @State private var isTransferring = false

    var body: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Section {
                Button("Transfer", systemImage: "arrow.left.arrow.right") { isTransferring = true }
            }
        }
        .sheet(isPresented: $isTransferring) {
            TransferEditor(viewedWallet: viewedWallet)
        }
    }

    /// The one wallet the tab is showing, or `nil` for the Total.
    private var viewedWallet: Wallet? {
        if case .wallet(let wallet) = walletSelection { wallet } else { nil }
    }
}
