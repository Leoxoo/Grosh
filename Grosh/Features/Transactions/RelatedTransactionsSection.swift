import SwiftData
import SwiftUI

/// The transaction detail's Related transactions: every transaction sharing its link, such as the other half of
/// a transfer. Each opens its own detail. Shows nothing when there are none. Use inside a `List`.
struct RelatedTransactionsSection: View {
    let transaction: Transaction

    @Environment(\.modelContext) private var context

    var body: some View {
        let related = (try? transaction.related(in: context)) ?? []
        if !related.isEmpty {
            Section("Related transactions") {
                ForEach(related) { other in
                    NavigationLink {
                        TransactionDetailView(transaction: other)
                    } label: {
                        RelatedTransactionRow(transaction: other)
                    }
                }
            }
        }
    }
}

/// A related transaction with its date, since it may fall on another day.
private struct RelatedTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TransactionRow(transaction: transaction)
            Text(transaction.day.date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)
        }
    }
}
