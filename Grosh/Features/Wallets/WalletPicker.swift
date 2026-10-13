import SwiftData
import SwiftUI

/// Picks a wallet, in the order the user set by dragging. Use it for every wallet choice. A transaction, transfer or
/// Card's paying wallet is picked from the unarchived wallets, so archived ones stay out and the order matches Home; a
/// filter picks from every wallet, archived ones included, or none. The Transfer sheet's pickers also show balances.
struct WalletPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Wallet?
    /// The first choice, which picks no wallet, such as "Any". `nil` offers wallets only.
    private let noneTitle: LocalizedStringKey?
    /// The day whose balances the picker shows, or `nil` to show none.
    private let balancesDay: CalendarDay?

    @Query private var wallets: [Wallet]

    /// Picks from the unarchived wallets.
    init(title: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.title = title
        _selection = selection
        noneTitle = nil
        balancesDay = nil
        _wallets = Query(Wallet.unarchived)
    }

    /// Picks from the unarchived wallets, showing each one's balance on `today`: the chosen wallet's in a small line
    /// under the row, and every wallet's in its option in the dropdown, so they can be compared before choosing.
    init(title: LocalizedStringKey, selection: Binding<Wallet?>, balancesAsOf today: CalendarDay) {
        self.title = title
        _selection = selection
        noneTitle = nil
        balancesDay = today
        _wallets = Query(Wallet.unarchived)
    }

    /// Picks from every wallet, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringKey, everyWalletOr noneTitle: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.title = title
        _selection = selection
        self.noneTitle = noneTitle
        balancesDay = nil
        _wallets = Query(Wallet.notDeleted)
    }

    var body: some View {
        if let balancesDay {
            Picker(selection: $selection) {
                ForEach(choices) { wallet in
                    Label {
                        Text(Self.name(of: wallet))
                        Text(wallet.pickerOptionBalance(asOf: balancesDay))
                    } icon: {
                        Image(systemName: wallet.symbolName)
                    }
                    .tag(Optional(wallet))
                }
            } label: {
                Text(title)
                if let selection {
                    Text(selection.pickerBalanceLine(asOf: balancesDay))
                }
            } currentValueLabel: {
                if let selection {
                    Text(Self.name(of: selection))
                }
            }
        } else {
            Picker(title, selection: $selection) {
                if let noneTitle {
                    Text(noneTitle).tag(Wallet?.none)
                }
                ForEach(choices) { wallet in
                    Label(Self.name(of: wallet), systemImage: wallet.symbolName)
                        .tag(Optional(wallet))
                }
            }
        }
    }

    /// The wallets offered, plus the current selection when it was archived after being picked (e.g. editing an old
    /// transaction), so the picker still shows it.
    private var choices: [Wallet] {
        guard let selection, !wallets.contains(selection) else { return wallets }
        return wallets + [selection]
    }

    /// What the picker calls `wallet`: its name, marked when it is archived.
    private static func name(of wallet: Wallet) -> String {
        wallet.isArchived ? "\(wallet.name) (Archived)" : wallet.name
    }
}
