import SwiftData
import SwiftUI

/// The Transactions tab's list. Its header holds the wallet selector and its balance, the period strip, and either the
/// period's Opening and Ending balances or, while a search or filter is on, the count and total of what matches. The
/// list then holds the transactions by day, newest first, or by category. Future also lists the Scheduled rows of
/// Recurring transactions still to come, by day. The "…" menu picks the time range and the grouping, and selects
/// transactions to delete. The Search button opens a field that narrows what is listed, and so do the filters: grouped,
/// selected and summed are the matching transactions only.
struct TransactionListView: View {
    /// The transaction whose detail is showing.
    @Binding var selectedTransaction: Transaction?

    @Environment(\.today) private var today

    var body: some View {
        TransactionListContent(
            selectedTransaction: $selectedTransaction, startingPeriod: .month(CalendarMonth(today))
        )
    }
}

/// The list behind ``TransactionListView``, holding the period it shows from the moment the tab opens.
private struct TransactionListContent: View {
    @Binding var selectedTransaction: Transaction?

    @NotDeletedTransactions private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Environment(\.today) private var today
    @State private var walletSelection = WalletSelection.total
    /// How long each period in the strip is, chosen in the "…" menu.
    @State private var timeRange = TimeRange.month
    @State private var period: Period
    /// Whether the period's transactions are grouped by day or by category, chosen in the "…" menu.
    @State private var grouping = TransactionGrouping.day
    /// Search text and filters. Searching looks across all time and every wallet; filters narrow the period.
    @State private var filter = TransactionFilter()
    /// Whether the search field is open, which the toolbar's Search button turns on.
    @State private var isSearchPresented = false
    /// How far the list has scrolled from its top, which the title fades with and the header rises with.
    /// Rises far enough that the Total reaches the middle of the bar's row, where the bar shows it in its place.
    @State private var scroll = TabRootScroll(rise: 63)
    /// Whether the list is choosing transactions to delete, and the ones chosen so far.
    @State private var isSelecting = false
    @State private var chosen = Set<Transaction>()

    init(selectedTransaction: Binding<Transaction?>, startingPeriod: Period) {
        _selectedTransaction = selectedTransaction
        _period = State(initialValue: startingPeriod)
    }

    /// The selected wallet's transactions, or the wallet filter's when one is set, as ledger entries.
    private var selected: [LedgerEntry] {
        filter.transactions(in: walletSelection, from: $transactions)
    }

    /// The periods the strip offers for `selected`, back to its first day with data.
    private func strip(for selected: [LedgerEntry]) -> [Period] {
        timeRange.periods(from: selected.firstDay, today: today)
    }

    /// The Current period: the period of the time range that holds today.
    private var currentPeriod: Period {
        timeRange.period(containing: today)
    }

    var body: some View {
        let selected = selected
        let periods = strip(for: selected)
        let shownDays = period.days(today: today)
        let shown = filter.listed(from: transactions, selected: selected, on: shownDays)
        // Future's Scheduled rows are listed by day, and only while nothing is searched, filtered or being selected.
        let scheduled: [ScheduledOccurrence] = period == .future && grouping == .day && !filter.isOn && !isSelecting
            ? recurringTransactions.scheduledOccurrences(selection: walletSelection, today: today)
            : []
        // The rows highlighted: the chosen ones while selecting, otherwise the one whose detail is showing.
        let highlighted = isSelecting ? chosen : Set([selectedTransaction].compactMap { $0 })

        list {
            if shown.isEmpty && filter.isOn {
                Section {
                    NoMatchingTransactionsView(filter: filter)
                }
            } else if shown.isEmpty && scheduled.isEmpty {
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

            switch grouping {
            case .day:
                TransactionDaySections(
                    transactions: shown, scheduled: scheduled, isSelected: { highlighted.contains($0) }
                ) { row($0) }
            case .category:
                ForEach(TransactionCategoryGroup.groups(of: shown)) { group in
                    Section {
                        GroupedForEach(group.transactions, isSelected: { highlighted.contains($0) }) {
                            row($0, showsDay: true)
                        }
                    } header: {
                        TransactionCategoryHeader(group: group)
                    }
                }
            }
        }
        // The matches start at the top, and the period's list again once the search is cleared. Only the list starts
        // over: the header with the period strip, below, keeps its place.
        .id(filter.isSearching)
        .roundedSectionsListStyle()
        .tracksTabRootScroll(scroll)
        // A bar rather than an inset, so the content scrolling under it fades as it does under the system bar.
        .safeAreaBar(edge: .top, spacing: 0) {
            VStack(spacing: 4) {
                VStack(spacing: 4) {
                    WalletSelector(selection: $walletSelection, today: today)
                        .hiddenOnceRisen(scroll)
                    PeriodStrip(periods: periods, selection: $period, current: currentPeriod, today: today)
                }
                .hiddenWhileSearching(filter)
                if filter.isOn {
                    FilterSummaryFigures(filter: $filter, transactions: shown)
                } else {
                    PeriodSummaryView(summary: PeriodSummary(of: selected, in: period, today: today), period: period)
                }
            }
            .padding(.vertical, 8)
            // Rises into the title's place as the list scrolls up, and moves down with the title on a pull.
            .modifier(RisingWithTitle(scroll: scroll))
        }
        .modifier(TransactionSearchField(text: $filter.searchText, isOpen: $isSearchPresented))
        .onChange(of: walletSelection) {
            // A wallet with a shorter history may not reach back to the period being shown.
            period.showCurrentPeriod(currentPeriod, unlessOfferedBy: strip(for: selected))
        }
        .onChange(of: filter.wallet) {
            period.showCurrentPeriod(currentPeriod, unlessOfferedBy: strip(for: selected))
        }
        .onChange(of: timeRange) {
            // Unlike a wallet change, a new time range always starts on the Current period, even from Future.
            period = currentPeriod
        }
        .transactionSelectionMode(
            isSelecting: $isSelecting, chosen: $chosen, title: String(localized: "Transactions")
        )
        .tabRootTitle("Transactions", scroll: scroll, showsSmallTitle: isSelecting) {
            WalletSelector(selection: $walletSelection, today: today, fillsWidth: false)
        }
        .toolbar {
            if !isSelecting {
                ToolbarItem(placement: .primaryAction) {
                    TransactionsMenu(
                        walletSelection: walletSelection, timeRange: $timeRange, grouping: $grouping,
                        startSelecting: startSelecting, filter: $filter
                    )
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button("Search", systemImage: "magnifyingglass") { isSearchPresented = true }
                }
                #endif
                #if !os(iOS)
                // On iPhone and iPad, Filters is in the "…" menu: beside the tab's title the bar has room for two
                // buttons (ADR-0009).
                ToolbarItem(placement: .primaryAction) {
                    TransactionFilterButton(filter: $filter)
                }
                #endif
            }
        }
        .addTransactionButton()
    }

    /// The list, choosing several transactions while selecting and otherwise opening the one tapped.
    @ViewBuilder
    private func list(@ViewBuilder content: () -> some View) -> some View {
        if isSelecting {
            List(selection: $chosen, content: content)
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
        } else {
            List(selection: $selectedTransaction, content: content)
        }
    }

    @ViewBuilder
    private func row(_ transaction: Transaction, showsDay: Bool = false) -> some View {
        // The Total with no wallet filter lists every wallet; a selected wallet or a wallet filter lists one.
        let showsWalletIcon = walletSelection == .total && filter.wallet == nil
        if isSelecting {
            TransactionRow(transaction: transaction, showsDay: showsDay, showsWalletIcon: showsWalletIcon)
                .tag(transaction)
        } else {
            NavigationLink(value: transaction) {
                TransactionRow(transaction: transaction, showsDay: showsDay, showsWalletIcon: showsWalletIcon)
            }
        }
    }

    private func startSelecting() {
        selectedTransaction = nil
        chosen = []
        isSelecting = true
    }
}

/// Moves the header up into the title's place, a point for each point the list scrolls until the title is gone, and
/// down with a pull past the list's top, as the title moves.
private struct RisingWithTitle: ViewModifier {
    let scroll: TabRootScroll

    func body(content: Content) -> some View {
        content.offset(y: scroll.pull - scroll.progress * scroll.rise)
    }
}

/// A category's icon and name, and its total for the period in plain text.
private struct TransactionCategoryHeader: View {
    let group: TransactionCategoryGroup

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(category: group.category, size: 20)
            Text(group.category?.name ?? String(localized: "Uncategorized"))
            Spacer()
            AmountText(amount: group.total, showsPlusSign: true, showsColor: false)
        }
        .textCase(nil)
    }
}

/// Adds the system search field. On iPhone and iPad it is there only while the Search button has it open, or search text
/// is left to clear, so it doesn't take room from the header the rest of the time. It hangs on an empty background
/// rather than on the list: a modifier that comes and goes on the list itself rebuilds the list, which loses its place
/// and redraws the period strip mid-animation. Mac keeps its search field in the toolbar, and has no Search button.
private struct TransactionSearchField: ViewModifier {
    @Binding var text: String
    @Binding var isOpen: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content.searchable(text: $text, prompt: "Note, category or amount")
        #else
        content.background {
            if isOpen || !text.isEmpty {
                Color.clear
                    .searchable(text: $text, isPresented: $isOpen, prompt: "Note, category or amount")
            }
        }
        #endif
    }
}
