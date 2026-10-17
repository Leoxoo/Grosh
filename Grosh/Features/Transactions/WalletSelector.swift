import SwiftData
import SwiftUI

/// The Wallet selector at the top of the Transactions tab: the selection's name and its balance today. Tapping it
/// opens the Select Wallet sheet to choose the Total or one wallet.
struct WalletSelector: View {
    @Binding var selection: WalletSelection
    let today: CalendarDay

    @Query(Wallet.unarchived) private var wallets: [Wallet]
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var isChoosing = false

    var body: some View {
        VStack(spacing: 2) {
            Button {
                isChoosing = true
            } label: {
                HStack(spacing: 4) {
                    Label(selection.name, systemImage: selection.symbolName)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("Wallet")
            .accessibilityValue(selection.name)
            .sheet(isPresented: $isChoosing) {
                SelectWalletSheet(selection: $selection, today: today)
            }

            Text(WalletBalances($transactions, asOf: today).balance(of: selection, wallets: wallets).formatted())
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
    }
}

extension WalletSelection {
    /// "Total", or the wallet's name.
    var name: String {
        switch self {
        case .total: String(localized: "Total")
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
