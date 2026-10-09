import SwiftData
import SwiftUI

/// Picks a wallet from the unarchived ones, in the order the user set by dragging. Use it for every wallet
/// choice (transactions, transfers, a Card's paying wallet) so archived wallets stay out and the order matches Home.
struct WalletPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Wallet?

    @Query(Wallet.unarchived) private var wallets: [Wallet]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices) { wallet in
                Label(wallet.name, systemImage: wallet.symbolName)
                    .tag(Optional(wallet))
            }
        }
    }

    /// The unarchived wallets, plus the current selection when it was archived after being picked
    /// (e.g. editing an old transaction), so the picker still shows it.
    private var choices: [Wallet] {
        guard let selection, !wallets.contains(selection) else { return wallets }
        return wallets + [selection]
    }
}
