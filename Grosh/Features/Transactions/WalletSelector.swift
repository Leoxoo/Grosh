import SwiftData
import SwiftUI

/// The Wallet selector at the top of the Transactions tab: the selection's name and its balance today. Tapping it
/// opens the Select Wallet sheet to choose the Total or one wallet.
struct WalletSelector: View {
    @Binding var selection: WalletSelection
    let today: CalendarDay
    /// Takes the width of the screen at the standard margin; off where it is placed from outside: in the bar, where it
    /// takes only its own, and in Transactions' header, which lines it up with the bar's (`linedUpWithTabRootTitle`).
    var fillsWidth = true

    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var isChoosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isChoosing = true
            } label: {
                HStack(spacing: 4) {
                    // Both, also in a toolbar, which would show only the icon.
                    Label(selection.name, systemImage: selection.symbolName)
                        .labelStyle(.titleAndIcon)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            // The app's green and the header's size, also in a toolbar, which tints its items its own way and makes them
            // larger.
            .tint(.accentColor)
            .controlSize(.regular)
            .imageScale(.medium)
            .fixedSize()
            .accessibilityLabel(Strings.Common.wallet)
            .accessibilityValue(selection.name)
            .sheet(isPresented: $isChoosing) {
                SelectWalletSheet(selection: $selection, today: today)
            }

            Text(WalletBalances($transactions, asOf: today).balance(of: selection, wallets: wallets).formatted())
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        // Under the tab's title, lined up with it.
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .padding(.horizontal, fillsWidth ? nil : 0)
    }
}

extension WalletSelection {
    /// "Total", or the wallet's name.
    var name: String {
        switch self {
        case .total: String(localized: Strings.Common.total)
        case .wallet(let wallet): wallet.name
        }
    }

    /// The Total's globe, or the wallet's own symbol.
    var symbolName: String {
        switch self {
        case .total: "globe"
        case .wallet(let wallet): wallet.symbolName
        }
    }
}
