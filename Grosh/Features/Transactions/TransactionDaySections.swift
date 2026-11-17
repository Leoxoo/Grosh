import SwiftUI

/// Transactions by day, newest day first. Each day is one card: its date and net total lead that day's transactions,
/// on the card with them. The Transactions tab's list and search results use it. `row` draws each transaction.
/// Future's Scheduled rows fall on their days after that day's transactions, and each opens its Recurring transaction.
/// Use inside a `List`.
struct TransactionDaySections<Row: View>: View {
    let transactions: [Transaction]
    /// Future's Scheduled rows: occurrences not yet made into transactions.
    var scheduled: [ScheduledOccurrence] = []
    /// Whether a transaction's row is highlighted. Only Mac draws the highlight, in the row's group.
    var isSelected: (Transaction) -> Bool = { _ in false }
    /// What each day's total adds up: the net, or on a Card's statement what the Card was charged.
    var listed = ListedAmount.net
    /// Whether Scheduled rows show their wallet's icon, as `row` does for a list that mixes wallets.
    var showsWalletIcon = true
    @ViewBuilder let row: (Transaction) -> Row

    var body: some View {
        ForEach(TransactionDay.days(of: transactions, scheduled: scheduled)) { day in
            let count = day.transactions.count + day.scheduled.count + 1
            Section {
                TransactionDayHeader(day: day, listed: listed)
                    .groupedRow(GroupPosition(index: 0, count: count))
                GroupedForEach(day.transactions, rowsBefore: 1, rowsInSection: count, isSelected: isSelected) { row($0) }
                GroupedForEach(day.scheduled, rowsBefore: day.transactions.count + 1, rowsInSection: count) { occurrence in
                    NavigationLink {
                        RecurringTransactionDetailView(recurring: occurrence.recurring)
                    } label: {
                        ScheduledRow(occurrence: occurrence, showsWalletIcon: showsWalletIcon)
                    }
                }
            }
        }
    }
}

/// A day's date on its card, with its day number big, the weekday and the month and year stacked small beside it,
/// and the day's total. At the largest text sizes the total moves under the date so neither is cut short. A day with
/// only Scheduled rows has no total.
struct TransactionDayHeader: View {
    let day: TransactionDay
    /// What the total adds up: the net, or on a Card's statement what the Card was charged.
    var listed = ListedAmount.net

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    private var hasTransactions: Bool { !day.transactions.isEmpty }

    var body: some View {
        let date = day.day.date()
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    dateLabel(date)
                    if hasTransactions { total }
                }
            } else {
                HStack(spacing: 8) {
                    dateLabel(date)
                    Spacer(minLength: 8)
                    if hasTransactions { total }
                }
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(hasTransactions ? day.total(listed).signedFormatted() : "")
    }

    private func dateLabel(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Text(date.formatted(.dateTime.day()))
                .font(.title.bold())
                .monospacedDigit()
                // The day's main number. White on a dark card; the label color there is a little gray. A light
                // appearance keeps the label color, so the number can still be read.
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.weekday(.wide)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(date.formatted(.dateTime.month(.wide).year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
    }

    private var total: some View {
        AmountText(amount: day.total(listed), showsPlusSign: true, showsColor: false)
            .font(.subheadline.weight(.semibold))
    }
}
