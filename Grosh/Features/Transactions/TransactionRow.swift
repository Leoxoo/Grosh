import SwiftUI

/// One transaction as every list shows it: category icon and name, note, Estimated and Forgiven badges, the Card's
/// symbol or image, the wallet icon, and the amount in color. A forgiven Loan or Debt keeps its true amount. An Expense
/// that was paid back keeps its original amount, lists its Reimbursements under the title and shows its net, except on
/// a Card's statement, which shows only what the Card was charged.
struct TransactionRow: View {
    let transaction: Transaction
    /// Shows the transaction's day, for lists not grouped by day.
    var showsDay = false
    /// Shows the paying wallet's icon in gray, for lists that mix wallets. A list of one wallet turns it off.
    var showsWalletIcon = true
    /// Whether the row shows a paid-back Expense's net beside its amount, or only what its Card was charged. In the Total
    /// the net also takes off what was paid back into other wallets there; in a wallet the row notes it instead.
    var listed = ListedAmount.net

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
                ReimbursementEntriesText(transaction: transaction, listed: listed)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    AmountText(amount: transaction.amount)
                    if listed != .charged {
                        ReimbursementNetText(transaction: transaction, listed: listed)
                    }
                }
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

/// The Card a transaction was paid with, in a fixed-size slot: its image as a landscape thumbnail, or else its symbol in
/// the Card's color. Its name is the accessibility label and a Mac hover tooltip.
struct CardIndicator: View {
    let card: Card

    var body: some View {
        CardMark(image: card.image, height: 15) {
            Image(systemName: Card.symbolName)
                .font(.caption)
                .foregroundStyle(card.color.color)
        }
        .frame(width: 24, height: 16)
        .accessibilityElement(children: .ignore)
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
    var categoryName: String { Category.name(of: category) }
}

extension Category {
    /// `category`'s name, or "Uncategorized" for none.
    static func name(of category: Category?) -> String {
        category?.name ?? String(localized: "Uncategorized")
    }
}
