import SwiftData
import SwiftUI

/// The Transactions tab's list: the wallet selector and its balance, the period strip, the period's Opening and
/// Ending balances, then its transactions by day, newest first, or by category. The "…" menu picks the time range
/// and the grouping, and selects transactions to delete. Search and the filters narrow what is listed: grouped,
/// selected and summed are the matching transactions only.
struct TransactionListView: View {
    /// The transaction whose detail is showing.
    @Binding var selectedTransaction: Transaction?

    @Query private var transactions: [Transaction]
    @State private var walletSelection = WalletSelection.total
    /// How long each period in the strip is, chosen in the "…" menu.
    @State private var timeRange = TimeRange.month
    @State private var period = Period.month(CalendarMonth(.today))
    /// Whether the period's transactions are grouped by day or by category, chosen in the "…" menu.
    @State private var grouping = TransactionGrouping.day
    /// Search text and filters. Searching looks across all time and every wallet; filters narrow the period.
    @State private var filter = TransactionFilter()
    /// Whether the list is choosing transactions to delete, and the ones chosen so far.
    @State private var isSelecting = false
    @State private var chosen = Set<Transaction>()
    @State private var deletePrompt: TransactionDeletePrompt?
    @State private var errorMessage: String?

    @Environment(\.modelContext) private var context

    private var today: CalendarDay { .today }

    /// The selected wallet's transactions, or the wallet filter's when one is set.
    private var selected: [Transaction] {
        filter.transactions(in: walletSelection, from: transactions)
    }

    /// The periods the strip offers for `selected`, back to its first day with data.
    private func strip(for selected: [Transaction]) -> [Period] {
        timeRange.periods(from: selected.firstDay, today: today)
    }

    var body: some View {
        let today = today
        let selected = selected
        let periods = strip(for: selected)
        let shownDays = period.days(today: today)
        let shown = filter.listed(from: transactions, selection: walletSelection, on: shownDays)

        list {
            Section {
                if filter.isOn {
                    FilterSummaryView(filter: $filter, transactions: shown)
                } else {
                    PeriodSummaryView(
                        summary: PeriodSummary(of: selected, in: period, today: today), period: period, today: today
                    )
                }
            }

            if shown.isEmpty && filter.isOn {
                Section {
                    NoMatchingTransactionsView(filter: filter)
                }
            } else if shown.isEmpty {
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
                ForEach(TransactionDay.days(of: shown)) { day in
                    Section {
                        rows(day.transactions)
                    } header: {
                        TransactionDayHeader(day: day)
                    }
                }
            case .category:
                ForEach(TransactionCategoryGroup.groups(of: shown)) { group in
                    Section {
                        rows(group.transactions, showsDay: true)
                    } header: {
                        TransactionCategoryHeader(group: group)
                    }
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
            .hiddenWhileSearching(filter)
        }
        .searchable(text: $filter.searchText, prompt: "Note, category or amount")
        .onChange(of: walletSelection) {
            // A wallet with a shorter history may not reach back to the period being shown.
            showPeriodHoldingTodayUnlessOffered(by: strip(for: selected))
        }
        .onChange(of: filter.wallet) {
            showPeriodHoldingTodayUnlessOffered(by: strip(for: selected))
        }
        .onChange(of: timeRange) {
            showPeriodHoldingTodayUnlessOffered(by: strip(for: selected))
        }
        .navigationTitle(isSelecting ? selectionTitle : String(localized: "Transactions"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { stopSelecting() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDeletingChosen() }
                        .disabled(chosen.isEmpty)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    TransactionsMenu(
                        walletSelection: walletSelection, timeRange: $timeRange, grouping: $grouping,
                        startSelecting: startSelecting
                    )
                }
                ToolbarItem(placement: .primaryAction) {
                    TransactionFilterButton(filter: $filter)
                }
            }
        }
        .transactionDeleteDialog($deletePrompt, didDelete: stopSelecting)
        .errorAlert("Couldn't Delete Transactions", message: $errorMessage)
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

    private func rows(_ transactions: [Transaction], showsDay: Bool = false) -> some View {
        ForEach(transactions) { transaction in
            if isSelecting {
                TransactionRow(transaction: transaction, showsDay: showsDay)
                    .tag(transaction)
            } else {
                NavigationLink(value: transaction) {
                    TransactionRow(transaction: transaction, showsDay: showsDay)
                }
            }
        }
    }

    /// Keeps the period being shown when the strip still offers it; otherwise shows the one holding today.
    private func showPeriodHoldingTodayUnlessOffered(by strip: [Period]) {
        if !strip.contains(period) {
            period = timeRange.period(containing: today)
        }
    }

    private var selectionTitle: String {
        chosen.isEmpty ? String(localized: "Select Transactions") : String(localized: "\(chosen.count) Selected")
    }

    private func startSelecting() {
        selectedTransaction = nil
        chosen = []
        isSelecting = true
    }

    private func stopSelecting() {
        isSelecting = false
        chosen = []
    }

    private func confirmDeletingChosen() {
        do {
            deletePrompt = try TransactionDeletePrompt(for: Array(chosen).inListOrder(), in: context)
        } catch {
            errorMessage = error.localizedDescription
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

/// A category's icon and name, and its total for the period in color.
private struct TransactionCategoryHeader: View {
    let group: TransactionCategoryGroup

    var body: some View {
        HStack(spacing: 8) {
            CategoryIcon(category: group.category, size: 20)
            Text(group.category?.name ?? String(localized: "Uncategorized"))
            Spacer()
            AmountText(amount: group.total, showsPlusSign: true)
        }
        .textCase(nil)
    }
}
