import SwiftUI

/// One transaction as every list shows it: category icon and name, note, Card badge, wallet icon, and the amount
/// in color.
struct TransactionRow: View {
    let transaction: Transaction
    /// Shows the transaction's day, for lists not grouped by day.
    var showsDay = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
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
                    if let card = transaction.card {
                        CardBadge(card: card)
                    }
                    if let wallet = transaction.wallet {
                        Image(systemName: wallet.symbolName)
                            .font(.caption)
                            .foregroundStyle(wallet.color.color)
                            .accessibilityLabel(wallet.name)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule naming the Card a transaction was paid with.
struct CardBadge: View {
    let card: Card

    var body: some View {
        Label(card.name, systemImage: Card.symbolName)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(card.color.color)
            .background(card.color.color.opacity(0.15), in: Capsule())
    }
}

extension Transaction {
    /// The category's name, or "Uncategorized" for a transaction filed under none.
    var categoryName: String {
        category?.name ?? String(localized: "Uncategorized")
    }
}
