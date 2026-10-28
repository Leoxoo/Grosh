import SwiftUI

/// A wallet's icon, name and balance, as listed on Home and in Account → Wallets. At the accessibility text sizes the
/// balance moves under the name, so neither is broken across lines.
struct WalletRow: View {
    let wallet: Wallet
    let today: CalendarDay
    /// Every wallet's balance today, added up at once, when the list has them; otherwise the row adds up the wallet's
    /// own transactions.
    var balances: WalletBalances?
    var showsTotalStatus = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let balance = balances?.balance(of: wallet) ?? wallet.balance(asOf: today)
        let stacks = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: stacks ? .top : .center, spacing: 12) {
            SymbolCircle(symbolName: wallet.symbolName, color: wallet.color)
            if stacks {
                VStack(alignment: .leading, spacing: 2) {
                    name
                    balanceText(balance)
                }
                Spacer(minLength: 0)
            } else {
                name
                Spacer()
                balanceText(balance)
            }
        }
        .contentShape(Rectangle())
    }

    /// The wallet's name, and "Not in Total" under it when the row says so.
    private var name: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(wallet.name)
            if showsTotalStatus && !wallet.includeInTotal {
                Text(Strings.Common.notInTotal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The balance on one line, red when it is below zero.
    private func balanceText(_ balance: Money) -> some View {
        Text(balance.formatted())
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(balance.cents < 0 ? balance.tint : .primary)
    }
}
