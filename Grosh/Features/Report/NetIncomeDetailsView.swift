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

    @Environment(\.today) private var today

    var body: some View {
        CountedHistoryReader(selection: walletSelection) { history in
            content(history)
        }
    }

    @ViewBuilder
    private func content(_ history: CountedHistory) -> some View {
        let counted = history.during(period, today: today)
        let rows = StepRow.rows(
            of: counted, currencyCode: history.currencyCode, for: timeRange,
            over: history.days(of: period, today: today), today: today
        )
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(Strings.Screens.netIncome)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    AmountText(
                        amount: PeriodTotals(of: counted, currencyCode: history.currencyCode).netIncome,
                        showsPlusSign: true
                    )
                        .font(.largeTitle.bold())
                        .contentTransition(.numericText())
                    StepColumns(steps: rows, currencyCode: history.currencyCode)
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
            walletSelection: $walletSelection, timeRange: $timeRange, period: $period, history: history,
            showsWalletSelector: false
        )
        .navigationTitle(Strings.Screens.netIncome)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
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
                SummaryFigure(title: Text(Strings.Common.income), value: Text(totals.income.formatted()).monospacedDigit())
                SummaryFigure(title: Text(Strings.Common.spent), value: Text(totals.spent.formatted()).monospacedDigit())
                SummaryFigure(
                    title: Text(Strings.Screens.netIncome),
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
    let currencyCode: String

    var body: some View {
        Chart {
            ForEach(steps) { row in
                BarMark(x: .value(Strings.Common.step, row.title), y: .value(Strings.Common.income, row.totals.income.cents))
                    .foregroundStyle(SpentOrIncome.income.color)
                BarMark(x: .value(Strings.Common.step, row.title), y: .value(Strings.Common.spent, -row.totals.spent.cents))
                    .foregroundStyle(SpentOrIncome.spent.color)
            }
            RuleMark(y: .value(Strings.Common.zero, 0))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .stepBarAxes(currencyCode: currencyCode)
    }
}
