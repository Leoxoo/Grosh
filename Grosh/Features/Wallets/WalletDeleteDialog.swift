import SwiftData
import SwiftUI

extension View {
    /// Warns that `wallet` and all its transactions and Recurring transactions will be deleted while it is set, then
    /// moves them to Recently Deleted as one item (``Wallet/delete(at:)``) and calls `didDelete`.
    func walletDeleteDialog(_ wallet: Binding<Wallet?>, didDelete: @escaping () -> Void = {}) -> some View {
        modifier(WalletDeleteDialog(wallet: wallet, didDelete: didDelete))
    }
}

private struct WalletDeleteDialog: ViewModifier {
    @Binding var wallet: Wallet?
    let didDelete: () -> Void

    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Strings.Wallets.deleteThisWallet,
                isPresented: Binding(get: { wallet != nil }, set: { if !$0 { wallet = nil } }),
                titleVisibility: .visible,
                presenting: wallet
            ) { wallet in
                Button(Strings.Wallets.deleteWallet, role: .destructive) { delete(wallet) }
                Button(Strings.Common.cancel, role: .cancel) {}
            } message: { wallet in
                Text(Strings.Wallets.deleteMessage(wallet.name, RecentlyDeleted.keptDays))
            }
            .errorAlert(Strings.Wallets.couldntDelete, message: $errorMessage)
    }

    private func delete(_ wallet: Wallet) {
        do {
            try wallet.delete()
            didDelete()
        } catch {
            Log.store.failed("Deleting a wallet", error)
            errorMessage = error.localizedDescription
        }
    }
}
