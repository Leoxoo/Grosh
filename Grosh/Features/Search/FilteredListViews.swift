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

/// A searched or filtered list's count and what the matches add up to, as a list section: how many transactions match
/// and their net total. With a Card filter on, that is the Card's total, to check against the bank's app. Use inside a
/// `List` section. The Transactions tab shows the same in its header with ``FilterSummaryFigures``.
struct FilterSummaryView: View {
    @Binding var filter: TransactionFilter
    /// The transactions the list shows.
    let transactions: [Transaction]

    var body: some View {
        // The section's rows on Mac: the count and total, and Clear Filters while a filter is set.
        let count = filter.hasFilters ? 3 : 2
        LabeledContent("Transactions") {
            Text(transactions.count.formatted())
                .monospacedDigit()
        }
        .groupedRow(GroupPosition(index: 0, count: count))
        LabeledContent(filter.totalTitle) {
            AmountText(amount: transactions.net, showsPlusSign: true)
                .fontWeight(.semibold)
        }
        .groupedRow(GroupPosition(index: 1, count: count))
        if filter.hasFilters {
            Button("Clear Filters", systemImage: "xmark.circle") { filter.clearFilters() }
                .groupedRow(GroupPosition(index: 2, count: count))
        }
    }
}

/// A searched or filtered list's count and total in the Transactions tab's header, in place of the period's balances,
/// with Clear Filters under them while a filter is set. With a Card filter on, the total is the Card's.
struct FilterSummaryFigures: View {
    @Binding var filter: TransactionFilter
    /// The transactions the list shows.
    let transactions: [Transaction]

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                SummaryFigure(
                    title: Text("Transactions"),
                    value: Text(transactions.count.formatted()).monospacedDigit()
                )
                SummaryFigure(
                    title: Text(verbatim: filter.totalTitle),
                    value: AmountText(amount: transactions.net, showsPlusSign: true)
                )
            }
            if filter.hasFilters {
                Button("Clear Filters", systemImage: "xmark.circle") { filter.clearFilters() }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
    }
}

private extension TransactionFilter {
    /// The title of the total: the Card's when a Card filter is on, otherwise the net total.
    var totalTitle: String {
        card.map { "\($0.name) total" } ?? String(localized: "Net total")
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
