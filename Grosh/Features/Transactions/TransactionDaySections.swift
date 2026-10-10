import SwiftUI

/// Transactions by day, newest day first, each day under its date and net total: the Transactions tab's list and
/// search results. `row` draws each transaction. Use inside a `List`.
struct TransactionDaySections<Row: View>: View {
    let transactions: [Transaction]
    @ViewBuilder let row: (Transaction) -> Row

    var body: some View {
        ForEach(TransactionDay.days(of: transactions)) { day in
            Section {
                ForEach(day.transactions) { transaction in
                    row(transaction)
                }
            } header: {
                TransactionDayHeader(day: day)
            }
        }
    }
}

/// A day's date and its net total in color.
struct TransactionDayHeader: View {
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
