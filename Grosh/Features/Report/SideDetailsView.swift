import Charts
import SwiftData
import SwiftUI

/// Income or Spent details: the period's total for the side and its Daily average, then either its Breakdown (a donut of
/// its parent categories and every parent category largest first, with its share) or its Trend (a bar per Step and a row
/// per Step). Tapping a category lists its transactions in the period; tapping a Step opens that Step's span alone. It
/// shares the Report's wallet selection, time range and period.
struct SideDetailsView: View {
    let side: SpentOrIncome
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period

    /// Whether the Breakdown or the Trend is shown, chosen with the segmented control.
    @State private var shows = Shows.breakdown
    /// Whether the comparison card compares with Last year, which Home's Month graph shares.
    @AppStorage(HomeMonthGraph.comparesWithLastYearKey) private var comparesWithLastYear = false

    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    @Query private var recurringTransactions: [RecurringTransaction]
    @Environment(\.today) private var today

    /// The two segments of the screen below its total.
    private enum Shows: Hashable {
        case breakdown
        case trend
    }

    var body: some View {
        OtherIncomeReader { otherIncome in
            content(otherIncome: otherIncome)
        }
    }

    /// The details, with Other Income read once for everything it counts.
    @ViewBuilder
    private func content(otherIncome: Category) -> some View {
        let days = transactions.reportDays(of: period, in: walletSelection, today: today)
        let counted = transactions.counted(in: walletSelection, during: period, today: today, otherIncome: otherIncome)
        let totals = PeriodTotals(of: counted)
        let total = side == .income ? totals.income : totals.spent
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(total.formatted())
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .foregroundStyle(side.color)
                        .contentTransition(.numericText())
                    if timeRange != .day, let average = DailyAverage.of(total, over: days) {
                        LabeledContent("Daily average") {
                            Text(average.formatted()).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            if timeRange.hasComparisonCard {
                let countedEver = transactions.compactMap {
                    $0.countedAmount(in: walletSelection, otherIncome: otherIncome)
                }
                PeriodComparisonCard(
                    graph: MonthGraph(
                        side, of: countedEver, countingFrom: countedEver.firstDay, recurring: recurringTransactions,
                        in: period, today: today, comparingWith: comparesWithLastYear ? .lastYear : .average,
                        selection: walletSelection
                    ),
                    comparesWithLastYear: $comparesWithLastYear
                )
            }

            Section {
                Picker("Shows", selection: $shows) {
                    Text("Breakdown").tag(Shows.breakdown)
                    Text("Trend").tag(Shows.trend)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            switch shows {
            case .breakdown:
                breakdown(counted: counted, days: days)
            case .trend:
                trend(counted: counted, days: days, today: today)
            }
        }
        .roundedSectionsListStyle()
        .reportPeriodControls(
            walletSelection: $walletSelection, timeRange: $timeRange, period: $period, transactions: transactions,
            showsWalletSelector: false
        )
        .navigationTitle(side.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func breakdown(counted: [CountedAmount], days: DayRange) -> some View {
        let breakdown = CategoryBreakdown(side: side, of: counted)
        Section {
            // The details show every parent category, not only the five largest the Report's donut does.
            CategoryDonut(breakdown: breakdown, ownSliceLimit: Int.max, minimumShare: 0.02)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }

        Section {
            ForEach(breakdown.categories, id: \.category) { row in
                NavigationLink(
                    value: ReportScreen.category(side, row.category, days: days, walletSelection: walletSelection)
                ) {
                    CategoryBreakdownRow(
                        category: row.category, total: row.total, share: breakdown.share(of: row.total)
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func trend(counted: [CountedAmount], days: DayRange, today: CalendarDay) -> some View {
        let rows = StepRow.rows(of: counted, for: timeRange, over: days, today: today)
        Section {
            SideTrendChart(side: side, rows: rows)
                .padding(.vertical, 8)
        }

        Section {
            ForEach(rows) { row in
                NavigationLink(
                    value: ReportScreen.stepTransactions(
                        side: side, title: row.title, days: row.step.days, walletSelection: walletSelection
                    )
                ) {
                    LabeledContent(row.title) {
                        Text(row.total(of: side).formatted())
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

/// A parent category's icon and name, its amount, and its share of the side, as a row of the Breakdown.
private struct CategoryBreakdownRow: View {
    let category: Category
    let total: Money
    let share: Double

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 32)
            Text(category.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(total.formatted())
                    .monospacedDigit()
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}

/// One bar per Step, in the side's color, the bar's height its total. The Steps are named under the bars, and the rows
/// below the chart list them with their totals.
private struct SideTrendChart: View {
    let side: SpentOrIncome
    let rows: [StepRow]

    var body: some View {
        Chart {
            ForEach(rows) { row in
                BarMark(x: .value("Step", row.title), y: .value("Total", row.total(of: side).cents))
                    .foregroundStyle(side.color)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let cents = value.as(Int.self) {
                        Text(Money(cents: cents).formatted())
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 260)
        .accessibilityHidden(true)
    }
}
