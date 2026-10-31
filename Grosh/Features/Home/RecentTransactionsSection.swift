import SwiftData
import SwiftUI

/// Home's Recent transactions: the latest few dated today or earlier. Each opens its detail.
/// Use inside a `List` within a `NavigationStack`.
struct RecentTransactionsSection: View {
    /// How many transactions Home shows.
    static let limit = 5

    @Query private var transactions: [Transaction]

    init(today: CalendarDay) {
        _transactions = Query(Transaction.recent(limit: Self.limit, asOf: today))
    }

    var body: some View {
        Section(Strings.Home.recentTransactions) {
            if transactions.isEmpty {
                Text(Strings.Home.recentTransactionsEmpty)
                    .foregroundStyle(.secondary)
            }
            ForEach(transactions.inListOrder()) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
        }
    }
}
