import SwiftData
import SwiftUI

/// Home's Month graph: the month strip, then the Spent card and the Income card, each with the running total of the
/// month the strip picks beside the Average of the months before it. Their amounts show even while the Total is hidden.
/// Use inside a `List`.
struct MonthGraphCards: View {
    let today: CalendarDay

    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    /// The month both cards show, picked in the strip. Every launch starts on this month.
    @State private var period = Period.month(CalendarMonth(.today))

    var body: some View {
        Section {
            PeriodStrip(periods: MonthGraph.months(of: transactions, today: today), selection: $period, today: today)
                // The strip pads its own tabs, and sits above the cards rather than on one.
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
        ForEach(SpentOrIncome.allCases, id: \.self) { side in
            MonthGraphCard(graph: MonthGraph(side, of: transactions, in: month, today: today))
        }
    }

    /// The month of the period picked in the strip, which offers only months.
    private var month: CalendarMonth {
        guard case .month(let month) = period else { return CalendarMonth(today) }
        return month
    }
}

/// A list section holding one card of the Month graph: its name, the month's total so far as its headline, the chart,
/// and the legend under it. It draws the graph as given, and keeps the day the user left the marker on.
struct MonthGraphCard: View {
    let graph: MonthGraph

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
                MonthGraphLegend(graph: graph)
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
        switch self {
        case .spent: Color("AmountRed")
        case .income: Color("AmountGreen")
        }
    }
}

#Preview {
    List {
        MonthGraphCards(today: .today)
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
