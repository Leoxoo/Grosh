import SwiftUI

/// A wallet's icon, name and balance, as listed on Home and in Account → Wallets.
struct WalletRow: View {
    let wallet: Wallet
    let today: CalendarDay
    /// Every wallet's balance today, added up at once, when the list has them; otherwise the row adds up the wallet's
    /// own transactions.
    var balances: WalletBalances?
    var showsTotalStatus = false

    var body: some View {
        let balance = balances?.balance(of: wallet) ?? wallet.balance(asOf: today)
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
                .foregroundStyle(balance.cents < 0 ? balance.tint : .primary)
        }
        .contentShape(Rectangle())
    }
}
