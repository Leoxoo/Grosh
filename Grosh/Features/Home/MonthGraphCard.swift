import SwiftData
import SwiftUI

/// Home's Month graph: the month strip, then one card with a Spent tab and an Income tab. The tab shown draws the
/// running total of the month the strip picks beside the Average of the months before it, or the same month last year
/// while the "vs last year" switch, which both tabs share, is on. A month the strip no longer offers, once the only
/// transaction that counted in it is gone, gives way to this month. Its amounts show even while the Total is hidden.
/// It reads only what the month picked needs from the store (``MonthGraphHistory``). Use inside a `List`.
struct HomeMonthGraph: View {
    /// Remembers across launches whether both tabs compare their month with Last year.
    static let comparesWithLastYearKey = "home.monthGraph.comparesWithLastYear"

    let today: CalendarDay

    @Query(MonthGraphHistory.earliestCounted) private var earliest: [Transaction]
    @Query(MonthGraphHistory.forgiven) private var forgiven: [Transaction]
    /// The month the card shows, picked in the strip. Every launch starts on this month.
    @State private var period = Period.month(CalendarMonth(.today))
    /// The tab the card shows.
    @State private var side = SpentOrIncome.spent
    @AppStorage(Self.comparesWithLastYearKey) private var comparesWithLastYear = false

    var body: some View {
        let firstDay = MonthGraphHistory.firstDay(earliest: earliest, forgiven: forgiven)
        let months = MonthGraph.months(from: firstDay, today: today)
        Section {
            PeriodStrip(periods: months, selection: $period, current: currentPeriod, today: today)
                // The strip pads its own tabs, and sits above the card rather than on it.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .onChange(of: months) { _, months in
                    period.showCurrentPeriod(currentPeriod, unlessOfferedBy: months)
                }
        }
        HomeMonthGraphCard(
            month: month, firstDay: firstDay, forgiven: forgiven, today: today, side: $side,
            comparesWithLastYear: $comparesWithLastYear
        )
    }

    /// The Current period: this month.
    private var currentPeriod: Period {
        TimeRange.month.period(containing: today)
    }

    /// The month of the period picked in the strip, which offers only months.
    private var month: CalendarMonth {
        guard case .month(let month) = period else { return CalendarMonth(today) }
        return month
    }
}

/// The card of the month picked in Home's strip, made from the transactions of the months its graphs sum, read from the
/// store for that month alone.
private struct HomeMonthGraphCard: View {
    let month: CalendarMonth
    /// The first day anything counts on the Month graph, or `nil` when nothing does.
    let firstDay: CalendarDay?
    /// Every forgiven Loan and Debt, which count on the day they were forgiven, whatever month that is.
    let forgiven: [Transaction]
    let today: CalendarDay
    @Binding var side: SpentOrIncome
    @Binding var comparesWithLastYear: Bool

    @Query private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]

    init(
        month: CalendarMonth, firstDay: CalendarDay?, forgiven: [Transaction], today: CalendarDay,
        side: Binding<SpentOrIncome>, comparesWithLastYear: Binding<Bool>
    ) {
        self.month = month
        self.firstDay = firstDay
        self.forgiven = forgiven
        self.today = today
        _side = side
        _comparesWithLastYear = comparesWithLastYear
        _transactions = Query(MonthGraphHistory.transactions(for: month))
    }

    var body: some View {
        let history = transactions + forgiven
        MonthGraphCard(
            spent: graph(for: .spent, of: history),
            income: graph(for: .income, of: history),
            side: $side,
            comparesWithLastYear: $comparesWithLastYear
        )
    }

    /// The graph of `side`'s tab for the month, compared as the "vs last year" switch is set.
    private func graph(for side: SpentOrIncome, of history: [Transaction]) -> MonthGraph {
        MonthGraph(
            side, of: history, countingFrom: firstDay, recurring: recurringTransactions, in: month, today: today,
            comparingWith: comparesWithLastYear ? .lastYear : .average
        )
    }
}

/// A list section holding the Month graph's card: a Spent tab and an Income tab, each naming its month's total so
/// far, then the chart of the tab shown and the legend under it with the "vs last year" switch. It draws the graphs as
/// given, and keeps the day the user left the marker on, whichever tab is shown.
struct MonthGraphCard: View {
    let spent: MonthGraph
    let income: MonthGraph
    /// The tab shown.
    @Binding var side: SpentOrIncome
    /// Whether the "vs last year" switch, which both tabs share, is on.
    @Binding var comparesWithLastYear: Bool

    /// The day the user last moved the marker to, or `nil` until they move it.
    @State private var scrubbedDay: CalendarDay?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    tab(spent)
                    tab(income)
                }
                MonthGraphChart(graph: graph, selection: selection)
                MonthGraphLegend(graph: graph, comparesWithLastYear: $comparesWithLastYear)
                    // Clear of the day numbers under the chart.
                    .padding(.top, 8)
            }
            .padding(.vertical, 4)
            // A day of another month isn't on this month's chart.
            .onChange(of: graph.month) { scrubbedDay = nil }
        }
    }

    /// The graph of the tab shown.
    private var graph: MonthGraph {
        side == .spent ? spent : income
    }

    /// The day the marker and popup are on: where the user left the marker, or the graph's default until they move it.
    private var selection: Binding<CalendarDay> {
        Binding(get: { scrubbedDay ?? graph.defaultSelection }, set: { scrubbedDay = $0 })
    }

    /// The tab of `tabGraph`: its name and the month's total so far in its color, over a bar that takes that color
    /// while the tab is shown.
    private func tab(_ tabGraph: MonthGraph) -> some View {
        let isShown = tabGraph.side == side
        return Button {
            withAnimation { side = tabGraph.side }
        } label: {
            VStack(spacing: 2) {
                Text(tabGraph.side.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(tabGraph.headline.formatted())
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(tabGraph.side.color)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Capsule()
                    .fill(isShown ? tabGraph.side.color : Color.secondary.opacity(0.3))
                    .frame(height: 3)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isShown ? .isSelected : [])
    }
}

extension SpentOrIncome {
    /// The tab's name on Home.
    var title: String {
        switch self {
        case .spent: String(localized: "Spent")
        case .income: String(localized: "Income")
        }
    }

    /// The color amounts going out (Spent) or coming in (Income) have everywhere in the app.
    var color: Color {
        Money(cents: self == .spent ? -1 : 1).tint
    }
}

#Preview {
    List {
        HomeMonthGraph(today: .today)
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
