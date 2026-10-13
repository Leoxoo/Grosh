import SwiftData
import SwiftUI

/// Picks a wallet, in the order the user set by dragging. Use it for every wallet choice. A transaction, transfer or
/// Card's paying wallet is picked from the unarchived wallets, so archived ones stay out and the order matches Home; a
/// filter picks from every wallet, archived ones included, or none. The Transfer sheet's pickers also show balances.
struct WalletPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Wallet?
    /// Which wallets the picker offers, and what it shows beside them.
    private let offered: Offered

    @Query private var wallets: [Wallet]

    /// What a picker can offer: the initializer used picks one.
    private enum Offered {
        /// The unarchived wallets.
        case unarchived
        /// The unarchived wallets, each with its balance on the day.
        case unarchivedWithBalances(CalendarDay)
        /// Every wallet, archived ones included, after a first choice that picks none, titled such as "Any".
        case everyWalletOr(LocalizedStringKey)

        /// The wallets to fetch for these choices.
        var wallets: FetchDescriptor<Wallet> {
            switch self {
            case .unarchived, .unarchivedWithBalances: Wallet.unarchived
            case .everyWalletOr: Wallet.notDeleted
            }
        }
    }

    /// Picks from the unarchived wallets.
    init(title: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.init(title: title, selection: selection, offered: .unarchived)
    }

    /// Picks from the unarchived wallets, showing each one's balance on `today`: the chosen wallet's in a small line
    /// under the row, and every wallet's in its option in the dropdown, so they can be compared before choosing.
    init(title: LocalizedStringKey, selection: Binding<Wallet?>, balancesAsOf today: CalendarDay) {
        self.init(title: title, selection: selection, offered: .unarchivedWithBalances(today))
    }

    /// Picks from every wallet, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringKey, everyWalletOr noneTitle: LocalizedStringKey, selection: Binding<Wallet?>) {
        self.init(title: title, selection: selection, offered: .everyWalletOr(noneTitle))
    }

    /// Picks from the wallets `offered` names, fetching just those.
    private init(title: LocalizedStringKey, selection: Binding<Wallet?>, offered: Offered) {
        self.title = title
        _selection = selection
        self.offered = offered
        _wallets = Query(offered.wallets)
    }

    var body: some View {
        if case .unarchivedWithBalances(let today) = offered {
            Picker(selection: $selection) {
                options(balancesAsOf: today)
            } label: {
                Text(title)
                if let selection {
                    Text(selection.balanceLine(asOf: today))
                }
            } currentValueLabel: {
                if let selection {
                    Text(Self.name(of: selection))
                }
            }
        } else {
            Picker(title, selection: $selection) {
                if case .everyWalletOr(let noneTitle) = offered {
                    Text(noneTitle).tag(Wallet?.none)
                }
                options(balancesAsOf: nil)
            }
        }
    }

    /// An option for each of the choices: the wallet's symbol and name, with its balance on `today` under the name when
    /// there is a day to show.
    private func options(balancesAsOf today: CalendarDay?) -> some View {
        ForEach(choices) { wallet in
            Label {
                Text(Self.name(of: wallet))
                if let today {
                    Text(wallet.balance(asOf: today).formatted())
                }
            } icon: {
                Image(systemName: wallet.symbolName)
            }
            .tag(Optional(wallet))
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
