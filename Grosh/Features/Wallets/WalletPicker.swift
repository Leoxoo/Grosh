import SwiftData
import SwiftUI

/// Picks a wallet, in the order the user set by dragging. Use it for every wallet choice. A transaction, transfer or
/// Card's paying wallet is picked from the unarchived wallets, so archived ones stay out and the order matches Home; a
/// filter picks from every wallet, archived ones included, or none.
struct WalletPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Wallet?
    /// The first choice, which picks no wallet, such as "Any". `nil` offers wallets only.
    private let noneTitle: LocalizedStringKey?

    @Query private var wallets: [Wallet]

    /// Picks from the unarchived wallets.
    init(title: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.title = title
        _selection = selection
        noneTitle = nil
        _wallets = Query(Wallet.unarchived)
    }

    /// Picks from every wallet, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringKey, everyWalletOr noneTitle: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.title = title
        _selection = selection
        self.noneTitle = noneTitle
        _wallets = Query(sort: Wallet.userOrder)
    }

    var body: some View {
        Picker(title, selection: $selection) {
            if let noneTitle {
                Text(noneTitle).tag(Wallet?.none)
            }
            ForEach(choices) { wallet in
                Label(wallet.isArchived ? "\(wallet.name) (Archived)" : wallet.name, systemImage: wallet.symbolName)
                    .tag(Optional(wallet))
            }
        }
    }

    /// The wallets offered, plus the current selection when it was archived after being picked (e.g. editing an old
    /// transaction), so the picker still shows it.
    private var choices: [Wallet] {
        guard let selection, !wallets.contains(selection) else { return wallets }
        return wallets + [selection]
    }
}
