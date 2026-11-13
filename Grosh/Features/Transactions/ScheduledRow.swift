import SwiftUI

/// A Scheduled row in Future: an upcoming occurrence of a Recurring transaction, labelled Scheduled, with its name,
/// signed amount and date. It is read-only: tapping it opens the Recurring transaction, not a transaction editor.
/// In a narrow column the name gives way first, so the badge, amount and date keep their full width.
struct ScheduledRow: View {
    let occurrence: ScheduledOccurrence
    /// Shows the wallet's icon in gray, as ``TransactionRow`` does, for lists that mix wallets.
    var showsWalletIcon = true

    /// The due day, such as "Mon, Oct 12". The year is left off because the day header above the row shows it.
    private var dayText: String {
        occurrence.day.date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: occurrence.recurring.category)
            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.recurring.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ScheduledBadge()
                    if occurrence.isEstimated {
                        EstimatedBadge()
                            .fixedSize()
                    }
                    if showsWalletIcon, let wallet = occurrence.recurring.wallet {
                        RowWalletIcon(wallet: wallet)
                    }
                }
            }
            VStack(alignment: .trailing, spacing: 4) {
                AmountText(amount: occurrence.amount)
                Text(dayText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A small capsule saying a row is a Scheduled occurrence, not a transaction yet. It never truncates its label.
struct ScheduledBadge: View {
    var body: some View {
        Label(Strings.Transactions.scheduled, systemImage: "calendar.badge.clock")
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .capsuleBadge(.secondary, on: .secondary)
    }
}
