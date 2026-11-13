import SwiftUI

/// The Report's Net income card: the period's Net income, signed and colored, then an Income bar and a Spent bar, each
/// labelled with its amount. The larger of the two fills the width and the other is drawn in proportion to it.
struct NetIncomeCard: View {
    let totals: PeriodTotals

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(Strings.Screens.netIncome)
                    .font(.headline)
                ExplanationButton(
                    label: Strings.Report.whatNetIncomeCounts,
                    explanation: String(localized: Strings.Report.netIncomeExplanation)
                )
            }

            AmountText(amount: totals.netIncome, showsPlusSign: true)
                .font(.largeTitle.bold())
                .contentTransition(.numericText())

            VStack(spacing: 12) {
                AmountBar(side: .income, totals: totals)
                AmountBar(side: .spent, totals: totals)
            }

            NavigationLink(value: ReportScreen.details(.netIncome)) {
                Text(Strings.Report.seeDetails)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One side's amount as a bar in its color, labelled with the side's name and amount. The larger side's bar fills the
/// width (``PeriodTotals/barFraction(of:)``).
private struct AmountBar: View {
    let side: SpentOrIncome
    let totals: PeriodTotals

    var body: some View {
        let amount = totals.total(of: side)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(side.title)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(amount.formatted())
                    .monospacedDigit()
            }
            .font(.subheadline)

            GeometryReader { proxy in
                Capsule()
                    .fill(side.color)
                    .frame(width: proxy.size.width * totals.barFraction(of: side))
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}
