import SwiftData
import SwiftUI

/// Search across all time and every wallet, archived ones included: note text, category name or amount, narrowed
/// by the filters. Each result opens its detail. Use inside a `NavigationStack`.
struct TransactionSearchView: View {
    @Query private var transactions: [Transaction]
    @State private var filter = TransactionFilter()
    @State private var isSearchPresented = true

    var body: some View {
        let results = filter.isOn ? transactions.matching(filter) : []

        List {
            if !results.isEmpty {
                Section {
                    FilterSummaryView(filter: $filter, transactions: results)
                }
            }

            TransactionDaySections(transactions: results) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .overlay {
            if !filter.isOn {
                ContentUnavailableView(
                    "Search Transactions",
                    systemImage: "magnifyingglass",
                    description: Text("Find a note, a category or an amount in every wallet, across all time.")
                )
            } else if results.isEmpty {
                NoMatchingTransactionsView(filter: filter)
            }
        }
        .searchable(text: $filter.searchText, isPresented: $isSearchPresented, prompt: "Note, category or amount")
        .navigationTitle("Search")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                TransactionFilterButton(filter: $filter)
            }
        }
    }
}

#Preview {
    NavigationStack {
        TransactionSearchView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
