import SwiftData
import SwiftUI

/// Search across all time and every wallet, archived ones included: note text, category name or amount, narrowed
/// by the filters. Each result opens its detail. Use inside a `NavigationStack`.
struct TransactionSearchView: View {
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var filter = TransactionFilter()
    @State private var isSearchPresented = true

    var body: some View {
        let listing = TransactionListing.search(transactions, filter: filter)
        let results = listing.transactions

        List {
            TransactionDaySections(transactions: results, listed: listing.listed) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction, showsWalletIcon: listing.mixesWallets, listed: listing.listed)
                }
            }
        }
        .roundedSectionsListStyle()
        // A bar rather than an inset, so the results scrolling under it fade as they do under the system bar.
        .safeAreaBar(edge: .top, spacing: 0) {
            if !results.isEmpty {
                FilterSummary(filter: $filter, listing: listing)
                    .padding(.vertical, 8)
            }
        }
        .overlay {
            if !filter.isOn {
                ContentUnavailableView(
                    Strings.Search.searchTransactions,
                    systemImage: "magnifyingglass",
                    description: Text(Strings.Search.searchDescription)
                )
            } else if results.isEmpty {
                NoMatchingTransactionsView(filter: filter)
            }
        }
        .searchable(text: $filter.searchText, isPresented: $isSearchPresented, prompt: Strings.Common.searchPrompt)
        .navigationTitle(Strings.Screens.search)
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
