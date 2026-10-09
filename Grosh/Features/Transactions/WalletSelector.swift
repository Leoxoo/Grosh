import SwiftData
import SwiftUI

/// The top of the Transactions tab: a menu choosing the Total or one wallet, and that selection's balance today.
struct WalletSelector: View {
    @Binding var selection: WalletSelection
    let today: CalendarDay

    @Query(Wallet.unarchived) private var wallets: [Wallet]

    var body: some View {
        VStack(spacing: 2) {
            Menu {
                Picker("Wallet", selection: $selection) {
                    Label("Total", systemImage: WalletSelection.total.symbolName)
                        .tag(WalletSelection.total)
                    ForEach(wallets) { wallet in
                        Label(wallet.name, systemImage: wallet.symbolName)
                            .tag(WalletSelection.wallet(wallet))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Label(selection.name, systemImage: selection.symbolName)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("Wallet")
            .accessibilityValue(selection.name)

            Text(selection.balance(asOf: today, wallets: wallets).formatted())
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

extension WalletSelection {
    var name: String {
        switch self {
        case .total: String(localized: "Total")
        case .wallet(let wallet): wallet.name
        }
    }

    var symbolName: String {
        switch self {
        case .total: "globe"
        case .wallet(let wallet): wallet.symbolName
        }
    }
}
