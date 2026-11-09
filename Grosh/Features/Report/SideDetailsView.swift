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
    @AppStorage(AppSettings.comparesWithLastYearKey) private var comparesWithLastYear = AppSettings.comparesWithLastYearDefault

    @Query private var recurringTransactions: [RecurringTransaction]
    @Environment(\.today) private var today

    /// The two segments of the screen below its total.
    private enum Shows: Hashable {
        case breakdown
        case trend
    }

    var body: some View {
        CountedHistoryReader(selection: walletSelection) { history in
            content(history)
        }
    }

    @ViewBuilder
    private func content(_ history: CountedHistory) -> some View {
        let days = history.days(of: period, today: today)
        let counted = history.during(period, today: today)
        let total = PeriodTotals(of: counted).total(of: side)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Strings.Common.total)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(total.formatted())
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .foregroundStyle(side.color)
                        .contentTransition(.numericText())
                    if timeRange != .day, let average = DailyAverage.of(total, over: days) {
                        LabeledContent(Strings.Report.dailyAverage) {
                            Text(average.formatted()).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Only a week, month, quarter or year has a graph. The period decides, not the time range: for a moment
            // after the time range changes, the period is still one of the old range.
            if let graph = history.graph(
                side, in: period, recurring: recurringTransactions, today: today,
                comparingWith: comparesWithLastYear ? .lastYear : .average
            ) {
                PeriodComparisonCard(graph: graph, comparesWithLastYear: $comparesWithLastYear)
            }

            Section {
                Picker(Strings.Report.shows, selection: $shows) {
                    Text(Strings.Report.breakdown).tag(Shows.breakdown)
                    Text(Strings.Report.trend).tag(Shows.trend)
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
            walletSelection: $walletSelection, timeRange: $timeRange, period: $period, history: history,
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
            CategoryDonut(breakdown: breakdown, donut: .details)
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
                        Text(row.totals.total(of: side).formatted())
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
                BarMark(
                    x: .value(Strings.Common.step, row.title), y: .value(Strings.Common.total, row.totals.total(of: side).cents)
                )
                .foregroundStyle(side.color)
            }
            RuleMark(y: .value(Strings.Common.zero, 0))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .stepBarAxes()
    }
}
