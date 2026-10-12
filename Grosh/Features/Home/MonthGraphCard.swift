import SwiftData
import SwiftUI

/// Home's Month graph: the month strip, then the Spent card and the Income card, each with the running total of the
/// month the strip picks beside the Average of the months before it, or the same month last year while that card's
/// switch is on. A month the strip no longer offers, once the only transaction that counted in it is gone, gives way to
/// this month. Their amounts show even while the Total is hidden. Use inside a `List`.
struct MonthGraphCards: View {
    /// Remembers across launches whether the Spent card compares its month with Last year.
    static let spentComparesWithLastYearKey = "home.monthGraph.spent.comparesWithLastYear"
    /// Remembers across launches whether the Income card compares its month with Last year.
    static let incomeComparesWithLastYearKey = "home.monthGraph.income.comparesWithLastYear"

    let today: CalendarDay

    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]
    /// The month both cards show, picked in the strip. Every launch starts on this month.
    @State private var period = Period.month(CalendarMonth(.today))
    @AppStorage(Self.spentComparesWithLastYearKey) private var spentComparesWithLastYear = false
    @AppStorage(Self.incomeComparesWithLastYearKey) private var incomeComparesWithLastYear = false

    var body: some View {
        let months = MonthGraph.months(of: transactions, today: today)
        Section {
            PeriodStrip(periods: months, selection: $period, current: currentPeriod, today: today)
                // The strip pads its own tabs, and sits above the cards rather than on one.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .onChange(of: months) { _, months in
                    period.showCurrentPeriod(currentPeriod, unlessOfferedBy: months)
                }
        }
        ForEach(SpentOrIncome.allCases, id: \.self) { side in
            let lastYearSwitch = comparesWithLastYear(side)
            MonthGraphCard(
                graph: MonthGraph(
                    side, of: transactions, recurring: recurringTransactions, in: month, today: today,
                    comparingWith: lastYearSwitch.wrappedValue ? .lastYear : .average
                ),
                comparesWithLastYear: lastYearSwitch
            )
        }
    }

    /// The "vs last year" switch of `side`'s card, each card's its own.
    private func comparesWithLastYear(_ side: SpentOrIncome) -> Binding<Bool> {
        switch side {
        case .spent: $spentComparesWithLastYear
        case .income: $incomeComparesWithLastYear
        }
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

/// A list section holding one card of the Month graph: its name, the month's total so far as its headline, the chart,
/// and the legend under it with the "vs last year" switch. It draws the graph as given, and keeps the day the user left
/// the marker on.
struct MonthGraphCard: View {
    let graph: MonthGraph
    /// Whether the card's "vs last year" switch is on.
    @Binding var comparesWithLastYear: Bool

    /// The day the user last moved the marker to, or `nil` until they move it.
    @State private var scrubbedDay: CalendarDay?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(graph.headline.formatted())
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                MonthGraphChart(graph: graph, selection: selection)
                MonthGraphLegend(graph: graph, comparesWithLastYear: $comparesWithLastYear)
            }
            .padding(.vertical, 4)
            // A day of another month isn't on this month's chart.
            .onChange(of: graph.month) { scrubbedDay = nil }
        } header: {
            Text(graph.side.title)
        }
        .headerProminence(.increased)
    }

    /// The day the marker and popup are on: where the user left the marker, or the graph's default until they move it.
    private var selection: Binding<CalendarDay> {
        Binding(get: { scrubbedDay ?? graph.defaultSelection }, set: { scrubbedDay = $0 })
    }
}

extension SpentOrIncome {
    /// The card's name on Home.
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
        MonthGraphCards(today: .today)
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
