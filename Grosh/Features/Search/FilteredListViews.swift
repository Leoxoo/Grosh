import SwiftUI

/// The Filters button, which opens the filters. Its icon fills while any filter is set. In a toolbar it opens them
/// itself; in a menu, which is gone by the time a sheet would open from it, it says On while a filter is set and its
/// screen opens them with ``transactionFilterSheet(isPresented:filter:)``.
struct TransactionFilterButton: View {
    @Binding var filter: TransactionFilter
    /// Set when the screen opens the sheet, as from a menu; `nil` when the button opens it itself.
    private let isPresentedByScreen: Binding<Bool>?

    @State private var isPresented = false

    /// A toolbar's Filters button.
    init(filter: Binding<TransactionFilter>) {
        _filter = filter
        isPresentedByScreen = nil
    }

    /// A menu's Filters item, setting `isPresented` for the screen to open the sheet.
    init(filter: Binding<TransactionFilter>, isPresented: Binding<Bool>) {
        _filter = filter
        isPresentedByScreen = isPresented
    }

    var body: some View {
        if let isPresentedByScreen {
            button { isPresentedByScreen.wrappedValue = true }
        } else {
            button { isPresented = true }
                .transactionFilterSheet(isPresented: $isPresented, filter: $filter)
        }
    }

    private func button(_ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            Label(
                Strings.Screens.filters,
                systemImage: filter.hasFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
            if isPresentedByScreen != nil, filter.hasFilters {
                Text(Strings.Common.on)
            }
        }
        .accessibilityValue(filter.hasFilters ? Text(Strings.Common.on) : Text(Strings.Common.off))
    }
}

/// A searched or filtered list's count and what the matches add up to (``TransactionListing/total``), in place of the
/// period's balances, with Clear Filters under them while a filter is set. With a Card filter on, the total is the
/// Card's, to check against the bank's app.
struct FilterSummary: View {
    @Binding var filter: TransactionFilter
    let listing: TransactionListing

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                SummaryFigure(
                    title: Text(Strings.Common.transactions),
                    value: Text(listing.transactions.count.formatted()).monospacedDigit()
                )
                SummaryFigure(
                    title: Text(verbatim: filter.totalTitle),
                    value: AmountText(amount: listing.total, showsPlusSign: true, showsColor: false)
                )
            }
            if filter.hasFilters {
                Button(Strings.Search.clearFilters, systemImage: "xmark.circle") { filter.clearFilters() }
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
        card.map { String(localized: Strings.Search.cardTotal($0.name)) } ?? String(localized: Strings.Search.netTotal)
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
                Strings.Search.noMatching,
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text(Strings.Search.tryChangingFilters)
            )
        }
    }
}

extension View {
    /// Opens the filters of `filter` in a sheet while `isPresented` is on.
    func transactionFilterSheet(isPresented: Binding<Bool>, filter: Binding<TransactionFilter>) -> some View {
        sheet(isPresented: isPresented) {
            TransactionFilterSheet(filter: filter)
        }
    }

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
                    Label(Strings.Screens.search, systemImage: "magnifyingglass")
                }
            }
        }
    }
}
