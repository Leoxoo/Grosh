import SwiftData
import SwiftUI

/// Picks a wallet, in the order the user set by dragging. Use it for every wallet choice. A transaction, transfer or
/// Card's paying wallet is picked from the unarchived wallets, so archived ones stay out and the order matches Home; a
/// filter picks from every wallet, archived ones included, or none. The Transfer sheet's pickers also show balances.
struct WalletPicker: View {
    let title: LocalizedStringResource
    var systemImage: String?
    @Binding var selection: Wallet?
    /// Which wallets the picker offers, and what it shows beside them.
    private let offered: Offered

    @Query private var wallets: [Wallet]

    /// What a picker can offer: the initializer used picks one.
    private enum Offered {
        /// The unarchived wallets.
        case unarchived
        /// The unarchived wallets, each with its balance.
        case unarchivedWithBalances(WalletBalances)
        /// Every wallet, archived ones included, after a first choice that picks none, titled such as "Any".
        case everyWalletOr(LocalizedStringResource)

        /// The wallets to fetch for these choices.
        var wallets: FetchDescriptor<Wallet> {
            switch self {
            case .unarchived, .unarchivedWithBalances: Wallet.unarchived
            case .everyWalletOr: Wallet.notDeleted
            }
        }
    }

    /// Picks from the unarchived wallets. With `systemImage`, the row is a compact one: the chosen wallet's colored
    /// symbol, or the icon while none is chosen, then its name.
    init(title: LocalizedStringResource, selection: Binding<Wallet?>, systemImage: String? = nil) {
        self.init(title: title, selection: selection, offered: .unarchived)
        self.systemImage = systemImage
    }

    /// Picks from the unarchived wallets, showing each one's balance from `balances`: the chosen wallet's on a Balance
    /// row of its own under the picker, and every wallet's in its option in the dropdown, so they can be compared before
    /// choosing. The row shows the chosen wallet's color.
    init(title: LocalizedStringResource, selection: Binding<Wallet?>, balances: WalletBalances) {
        self.init(title: title, selection: selection, offered: .unarchivedWithBalances(balances))
    }

    /// Picks from every wallet, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringResource, everyWalletOr noneTitle: LocalizedStringResource, selection: Binding<Wallet?>) {
        self.init(title: title, selection: selection, offered: .everyWalletOr(noneTitle))
    }

    /// Picks from the wallets `offered` names, fetching just those.
    private init(title: LocalizedStringResource, selection: Binding<Wallet?>, offered: Offered) {
        self.title = title
        _selection = selection
        self.offered = offered
        _wallets = Query(offered.wallets)
    }

    var body: some View {
        switch offered {
        case .unarchivedWithBalances(let balances):
            LabeledContent(title) {
                walletMenu(balances: balances)
            }
            if let selection {
                LabeledContent(Strings.Common.balance) {
                    AmountText(amount: balances.balance(of: selection), showsColor: false)
                }
            }
        case .unarchived where systemImage != nil:
            FormFieldRow(compact: true, leading: walletRowMark) {
                walletMenu(balances: nil)
            }
        default:
            Picker(title, selection: $selection) {
                if case .everyWalletOr(let noneTitle) = offered {
                    Text(noneTitle).tag(Wallet?.none)
                }
                options(balances: nil)
            }
        }
    }

    /// A menu of the wallets drawn as ``selectionLabel``.
    @ViewBuilder
    private func walletMenu(balances: WalletBalances?) -> some View {
        let menu = Menu {
            Picker(title, selection: $selection) {
                options(balances: balances)
            }
            .pickerStyle(.inline)
        } label: {
            selectionLabel
        }
        .menuStyle(.button)
        if systemImage != nil {
            menu.buttonStyle(.plain)
        } else {
            menu.buttonStyle(.borderless)
        }
    }

    /// The compact row's mark: the chosen wallet's symbol on its colored circle, or the field's icon while none is
    /// chosen.
    @ViewBuilder
    private var walletRowMark: some View {
        if let selection {
            SymbolCircle(symbolName: selection.symbolName, color: selection.color, size: 28)
                .accessibilityLabel(Text(title))
        } else {
            FieldLabel(title: title, systemImage: systemImage)
        }
    }

    /// The chosen wallet as the row shows it: its symbol on its colored circle (the compact row's mark instead) and its
    /// name, on one line however long the name is. A picker's own row can't show the color, so this draws the menu's
    /// button itself.
    private var selectionLabel: some View {
        HStack(spacing: 8) {
            if let selection {
                if systemImage == nil {
                    SymbolCircle(symbolName: selection.symbolName, color: selection.color)
                }
                Text(Self.name(of: selection))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            } else {
                Text(Strings.Common.choose)
                    .foregroundStyle(.secondary)
            }
            if systemImage != nil {
                Spacer(minLength: 0)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: systemImage != nil ? .infinity : nil, alignment: .leading)
    }

    /// An option for each of the choices: the wallet's symbol and name, with its balance under the name when there are
    /// balances to show.
    private func options(balances: WalletBalances?) -> some View {
        ForEach(choices) { wallet in
            Label {
                Text(Self.name(of: wallet))
                if let balances {
                    Text(balances.balance(of: wallet).formatted())
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
        wallet.isArchived ? String(localized: Strings.Common.archivedName(wallet.name)) : wallet.name
    }
}
