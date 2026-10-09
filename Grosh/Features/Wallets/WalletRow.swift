import SwiftUI

extension Wallet {
    var color: PaletteColor { PaletteColor(rawValue: colorName) ?? .green }
}

/// A wallet's icon, name and balance, as listed on Home and in Account → Wallets.
struct WalletRow: View {
    let wallet: Wallet
    let today: CalendarDay
    var showsTotalStatus = false

    var body: some View {
        let balance = wallet.balance(asOf: today)
        HStack(spacing: 12) {
            SymbolCircle(symbolName: wallet.symbolName, color: wallet.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name)
                if showsTotalStatus && !wallet.includeInTotal {
                    Text("Not in Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(balance.formatted())
                .monospacedDigit()
                .foregroundStyle(balance.cents < 0 ? .red : .primary)
        }
        .contentShape(Rectangle())
    }
}
