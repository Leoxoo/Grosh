import Charts
import SwiftData
import SwiftUI

/// Net income details: the period's Net income, a column per Step with Income above zero and Spent below it, and a row
/// per Step with its Income, Spent and Net. Tapping a row opens that Step's span alone. It shares the Report's wallet
/// selection, time range and period.
struct NetIncomeDetailsView: View {
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period

    @Query(Transaction.notDeleted) private var transactions: [Transaction]

    var body: some View {
        OtherIncomeReader { otherIncome in
            content(otherIncome: otherIncome)
        }
    }

    /// The details, with Other Income read once for everything it counts.
    @ViewBuilder
    private func content(otherIncome: Category) -> some View {
        let today = CalendarDay.today
        let counted = transactions.counted(in: walletSelection, during: period, today: today, otherIncome: otherIncome)
        let rows = stepRows(counted: counted, today: today)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Net income")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AmountText(amount: PeriodTotals(of: counted).netIncome, showsPlusSign: true)
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                    StepColumns(steps: rows)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(rows) { row in
                    NavigationLink(
                        value: ReportScreen.stepTransactions(
                            side: nil, title: row.title, days: row.step.days, walletSelection: walletSelection
                        )
                    ) {
                        StepTotalsRow(title: row.title, totals: row.totals)
                    }
                }
            }
        }
        .roundedSectionsListStyle()
        .reportPeriodControls(
            walletSelection: $walletSelection, timeRange: $timeRange, period: $period, transactions: transactions,
            showsWalletSelector: false
        )
        .navigationTitle("Net income")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// The Steps of the period as shown, each with its title and totals: what counts in each.
    private func stepRows(counted: [CountedAmount], today: CalendarDay) -> [StepRow] {
        let days = transactions.reportDays(of: period, in: walletSelection, today: today)
        return StepRow.rows(of: counted, for: timeRange, over: days, today: today)
    }
}

/// A Step's name over its Income, Spent and Net, the row a details screen lists the Steps by.
private struct StepTotalsRow: View {
    let title: String
    let totals: PeriodTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack(alignment: .top, spacing: 8) {
                SummaryFigure(title: Text("Income"), value: Text(totals.income.formatted()).monospacedDigit())
                SummaryFigure(title: Text("Spent"), value: Text(totals.spent.formatted()).monospacedDigit())
                SummaryFigure(
                    title: Text("Net income"),
                    value: AmountText(amount: totals.netIncome, showsPlusSign: true, showsColor: false)
                )
            }
        }
        .padding(.vertical, 2)
    }
}

/// One column per Step, Income above zero and Spent below it, in their colors. The Steps are named under the columns, and the
/// rows below the chart list them with their totals.
private struct StepColumns: View {
    let steps: [StepRow]

    var body: some View {
        Chart {
            ForEach(steps) { row in
                BarMark(x: .value("Step", row.title), y: .value("Income", row.totals.income.cents))
                    .foregroundStyle(SpentOrIncome.income.color)
                BarMark(x: .value("Step", row.title), y: .value("Spent", -row.totals.spent.cents))
                    .foregroundStyle(SpentOrIncome.spent.color)
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .chartXAxis {
            // Anchored, as the default label of a bar's category isn't one Charts accepts.
            AxisMarks { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(anchor: .top)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel(anchor: .trailing) {
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
