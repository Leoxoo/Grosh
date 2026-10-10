import SwiftUI

/// The toolbar button that opens the filters. Its icon fills while any filter is set.
struct TransactionFilterButton: View {
    @Binding var filter: TransactionFilter

    @State private var isPresented = false

    var body: some View {
        Button(
            "Filters",
            systemImage: filter.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
        ) {
            isPresented = true
        }
        .accessibilityValue(filter.hasFilters ? Text("On") : Text("Off"))
        .sheet(isPresented: $isPresented) {
            TransactionFilterSheet(filter: $filter)
        }
    }
}

/// The header of a searched or filtered list, in place of the period's balances: how many transactions match and
/// what they add up to. With a Card filter on, that is the Card's total, to check against the bank's app.
/// Use inside a `List` section.
struct FilterSummaryView: View {
    @Binding var filter: TransactionFilter
    /// The transactions the list shows.
    let transactions: [Transaction]

    var body: some View {
        LabeledContent("Transactions") {
            Text(transactions.count.formatted())
                .monospacedDigit()
        }
        LabeledContent(filter.card.map { "\($0.name) total" } ?? String(localized: "Net total")) {
            AmountText(amount: transactions.net, showsPlusSign: true)
                .fontWeight(.semibold)
        }
        if filter.hasFilters {
            Button("Clear Filters", systemImage: "xmark.circle") {
                filter = TransactionFilter(searchText: filter.searchText)
            }
        }
    }
}

/// What a searched or filtered list shows when nothing matches.
struct NoMatchingTransactionsView: View {
    let filter: TransactionFilter

    var body: some View {
        if filter.isSearching {
            ContentUnavailableView.search(text: filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            ContentUnavailableView(
                "No Matching Transactions",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try changing the filters.")
            )
        }
    }
}

extension View {
    /// Removes the view while `filter` is searching, as the selected wallet and period are: search looks past them.
    @ViewBuilder
    func hiddenWhileSearching(_ filter: TransactionFilter) -> some View {
        if !filter.isSearching {
            self
        }
    }

    /// Adds a Search button to the toolbar that opens ``TransactionSearchView``. Use it inside a `NavigationStack`.
    func transactionSearchButton() -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    TransactionSearchView()
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
        }
    }
}
