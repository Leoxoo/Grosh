import SwiftUI

/// One transaction as every list shows it: category icon and name, note, Estimated and Forgiven badges, the Card's
/// symbol, the wallet icon, and the amount in color. A forgiven Loan or Debt keeps its true amount.
struct TransactionRow: View {
    let transaction: Transaction
    /// Shows the transaction's day, for lists not grouped by day.
    var showsDay = false
    /// Shows the paying wallet's icon in gray, for lists that mix wallets. A list of one wallet turns it off.
    var showsWalletIcon = true

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category, subscriptionIcon: transaction.recurring?.subscriptionIcon)
            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.categoryName)
                    .lineLimit(1)
                if showsDay {
                    Text(transaction.day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !transaction.note.isEmpty {
                    Text(transaction.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                AmountText(amount: transaction.amount)
                HStack(spacing: 6) {
                    if transaction.isEstimated {
                        EstimatedBadge()
                    }
                    if transaction.isForgiven {
                        ForgivenBadge()
                    }
                    if let card = transaction.card {
                        CardIndicator(card: card)
                    }
                    if showsWalletIcon, let wallet = transaction.wallet {
                        Image(systemName: wallet.symbolName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(wallet.name)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The Card a transaction was paid with, drawn as its symbol in the Card's color. Its name is the accessibility label
/// and a Mac hover tooltip.
struct CardIndicator: View {
    let card: Card

    var body: some View {
        Image(systemName: Card.symbolName)
            .font(.caption)
            .foregroundStyle(card.color.color)
            .accessibilityLabel(card.name)
            .help(Text(card.name))
    }
}

/// A small capsule marking a transaction whose amount is still an estimate, until the real one is entered.
struct EstimatedBadge: View {
    var body: some View {
        Text("est.")
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.orange)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .accessibilityLabel("Estimated")
    }
}

/// A small capsule saying a Loan or Debt was forgiven.
struct ForgivenBadge: View {
    var body: some View {
        Label("Forgiven", systemImage: "hand.raised.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(.green)
            .background(Color.green.opacity(0.15), in: Capsule())
    }
}

extension Transaction {
    /// The category's name, or "Uncategorized" for a transaction filed under none.
    var categoryName: String {
        category?.name ?? String(localized: "Uncategorized")
    }
}
