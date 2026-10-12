import SwiftUI

/// Transactions by day, newest day first, each day under its date and net total: the Transactions tab's list and
/// search results. `row` draws each transaction. Future's Scheduled rows fall on their days after that day's
/// transactions, and each opens its Recurring transaction. Use inside a `List`.
struct TransactionDaySections<Row: View>: View {
    let transactions: [Transaction]
    /// Future's Scheduled rows: occurrences not yet made into transactions.
    var scheduled: [ScheduledOccurrence] = []
    /// Whether a transaction's row is highlighted. Only Mac draws the highlight, in the row's group.
    var isSelected: (Transaction) -> Bool = { _ in false }
    @ViewBuilder let row: (Transaction) -> Row

    var body: some View {
        ForEach(TransactionDay.days(of: transactions, scheduled: scheduled)) { day in
            let count = day.transactions.count + day.scheduled.count
            Section {
                GroupedForEach(day.transactions, rowsInSection: count, isSelected: isSelected) { row($0) }
                GroupedForEach(day.scheduled, rowsBefore: day.transactions.count, rowsInSection: count) { occurrence in
                    NavigationLink {
                        RecurringTransactionDetailView(recurring: occurrence.recurring)
                    } label: {
                        ScheduledRow(occurrence: occurrence)
                    }
                }
            } header: {
                TransactionDayHeader(day: day)
            }
        }
    }
}

/// A day's date with its day number big, the weekday and the month and year stacked small beside it, and the day's
/// net total. At the largest text sizes the total moves under the date so neither is cut short. A day with
/// only Scheduled rows has no total.
struct TransactionDayHeader: View {
    let day: TransactionDay

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .accessibilityValue(hasTransactions ? day.net.signedFormatted() : "")
    }

    private func dateLabel(_ date: Date) -> some View {
        HStack(spacing: 8) {
            Text(date.formatted(.dateTime.day()))
                .font(.title.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
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
        AmountText(amount: day.net, showsPlusSign: true, showsColor: false)
            .font(.subheadline.weight(.semibold))
    }
}
