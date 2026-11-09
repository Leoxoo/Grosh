import SwiftUI

/// One transaction as every list shows it: category icon and name, note, Estimated and Forgiven badges, the Card's
/// symbol or image, the wallet icon, and the amount in color. A forgiven Loan or Debt keeps its true amount. An Expense
/// that was paid back keeps its original amount, lists its Reimbursements under the title and shows its net, except on
/// a Card's statement, which shows only what the Card was charged. At the accessibility text sizes the amount moves
/// under the name, so neither is cut short.
struct TransactionRow: View {
    let transaction: Transaction
    /// Shows the transaction's day, for lists not grouped by day.
    var showsDay = false
    /// Shows the paying wallet's icon in gray, for lists that mix wallets. A list of one wallet turns it off.
    var showsWalletIcon = true
    /// Whether the row shows a paid-back Expense's net beside its amount, or only what its Card was charged. In the Total
    /// the net also takes off what was paid back into other wallets there; in a wallet the row notes it instead.
    var listed = ListedAmount.net

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // At the accessibility text sizes the amounts go under the name, where they have the row's full width.
        let stacks = dynamicTypeSize.isAccessibilitySize
        HStack(alignment: stacks ? .top : .center, spacing: 12) {
            CategoryIcon(category: transaction.category, subscriptionIcon: transaction.recurring?.subscriptionIcon)
            if stacks {
                VStack(alignment: .leading, spacing: 4) {
                    details(nameLines: 3)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { amounts }
                        VStack(alignment: .leading, spacing: 2) { amounts }
                    }
                    HStack(spacing: 6) { marks }
                }
                Spacer(minLength: 0)
            } else {
                details(nameLines: 1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) { amounts }
                    HStack(spacing: 6) { marks }
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The category name, with the day, note and Reimbursements under it.
    private func details(nameLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(transaction.categoryName)
                .lineLimit(nameLines)
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
    }

    /// The amount, and a paid-back Expense's net when the row shows it.
    @ViewBuilder
    private var amounts: some View {
        AmountText(amount: transaction.amount)
        if listed != .charged {
            ReimbursementNetText(transaction: transaction, listed: listed)
        }
    }

    /// The Estimated and Forgiven badges, the Card, and the wallet icon.
    @ViewBuilder
    private var marks: some View {
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
            RowWalletIcon(wallet: wallet)
        }
    }
}

/// The Card a transaction was paid with, in a fixed-size slot: its image as a landscape thumbnail, or else its symbol in
/// the Card's color. Its name is the accessibility label and a Mac hover tooltip.
struct CardIndicator: View {
    let card: Card

    var body: some View {
        CardMark(card: card, height: 15, symbolFont: .caption)
        .frame(width: 24, height: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.name)
        .help(Text(card.name))
    }
}

/// The paying wallet's icon in gray, which a transaction or Scheduled row shows in a list that mixes wallets.
struct RowWalletIcon: View {
    let wallet: Wallet

    var body: some View {
        Image(systemName: wallet.symbolName)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(wallet.name)
    }
}

/// A small capsule marking a transaction whose amount is still an estimate, until the real one is entered.
struct EstimatedBadge: View {
    var body: some View {
        Text(Strings.Transactions.estimatedShort)
            .capsuleBadge(.attention, on: .attention)
            .accessibilityLabel(Strings.Transactions.estimated)
    }
}

/// A small capsule saying a Loan or Debt was forgiven.
struct ForgivenBadge: View {
    var body: some View {
        Label(Strings.Common.forgiven, systemImage: "hand.raised.fill")
            .labelStyle(.titleAndIcon)
            .capsuleBadge(.settled, on: .settled)
    }
}
