import SwiftData
import SwiftUI

/// The Transactions tab's list: the wallet selector and its balance, the period strip, the period's Opening and
/// Ending balances, then its transactions by day, newest first.
struct TransactionListView: View {
    /// The transaction whose detail is showing.
    @Binding var selectedTransaction: Transaction?

    @Query private var transactions: [Transaction]
    @State private var walletSelection = WalletSelection.total
    /// How long each period in the strip is. Only a month for now; the "…" menu will choose it once it has
    /// more ranges to offer.
    @State private var timeRange = TimeRange.month
    @State private var period = Period.month(CalendarMonth(.today))

    private var today: CalendarDay { .today }

    /// The periods the strip offers for `selected`, back to its first day with data.
    private func strip(for selected: [Transaction]) -> [Period] {
        timeRange.periods(from: selected.map(\.dayRaw).min().map(CalendarDay.init(rawValue:)), today: today)
    }

    var body: some View {
        let today = today
        let selected = transactions.filter(walletSelection.includes)
        let periods = strip(for: selected)
        let shownDays = period.days(today: today)
        let days = TransactionDay.days(of: selected.filter { shownDays.contains($0.day) })

        List(selection: $selectedTransaction) {
            Section {
                PeriodSummaryView(summary: PeriodSummary(of: selected, in: period, today: today), period: period)
            }

            if days.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text(period == .future
                            ? "Transactions dated after today show up here."
                            : "Nothing was recorded in this period.")
                    )
                }
            }

            ForEach(days) { day in
                Section {
                    ForEach(day.transactions) { transaction in
                        NavigationLink(value: transaction) {
                            TransactionRow(transaction: transaction)
                        }
                    }
                } header: {
                    TransactionDayHeader(day: day)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 4) {
                WalletSelector(selection: $walletSelection, today: today)
                PeriodStrip(periods: periods, selection: $period, today: today)
            }
            .padding(.top, 8)
            .background(.bar)
        }
        .onChange(of: walletSelection) {
            // A wallet with a shorter history may not reach back to the period being shown.
            if !strip(for: transactions.filter(walletSelection.includes)).contains(period) {
                period = .month(CalendarMonth(today))
            }
        }
        .navigationTitle("Transactions")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                TransactionsMenu(walletSelection: walletSelection)
            }
        }
        .addTransactionButton()
    }
}

/// A day's date and its net total in color.
private struct TransactionDayHeader: View {
    let day: TransactionDay

    var body: some View {
        HStack {
            Text(day.day.date().formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
            Spacer()
            AmountText(amount: day.net, showsPlusSign: true)
        }
        .textCase(nil)
    }
}
