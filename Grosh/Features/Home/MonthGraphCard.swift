import SwiftData
import SwiftUI

/// Home's Month graph: the Spent card and the Income card, each with the running total of this month so far. Their
/// amounts show even while the Total is hidden. Use inside a `List`.
struct MonthGraphCards: View {
    let today: CalendarDay

    @Query(Transaction.notDeleted) private var transactions: [Transaction]

    var body: some View {
        ForEach(SpentOrIncome.allCases, id: \.self) { side in
            MonthGraphCard(graph: MonthGraph(side, of: transactions, in: CalendarMonth(today), today: today))
        }
    }
}

/// A list section holding one card of the Month graph: its name, the month's total so far as its headline, and the
/// chart. It draws the graph as given.
struct MonthGraphCard: View {
    let graph: MonthGraph

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(graph.headline.formatted())
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                MonthGraphChart(graph: graph)
            }
            .padding(.vertical, 4)
        } header: {
            Text(graph.side.title)
        }
        .headerProminence(.increased)
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
