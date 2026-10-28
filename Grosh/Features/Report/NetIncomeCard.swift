import SwiftUI

/// The Report's Net income card: the period's Net income, signed and colored, then an Income bar and a Spent bar, each
/// labelled with its amount. The larger of the two fills the width and the other is drawn in proportion to it.
struct NetIncomeCard: View {
    let totals: PeriodTotals
    /// Whether the ⓘ explanation is showing.
    @State private var isExplaining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Text(Strings.Screens.netIncome)
                    .font(.headline)
                Button {
                    isExplaining = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Strings.Report.whatNetIncomeCounts)
                .popover(isPresented: $isExplaining) {
                    Text(Self.explanation)
                        .font(.subheadline)
                        .padding()
                        .frame(maxWidth: 320, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                }
            }

            AmountText(amount: totals.netIncome, showsPlusSign: true)
                .font(.largeTitle.bold())
                .contentTransition(.numericText())

            let largest = max(totals.income.cents, totals.spent.cents)
            VStack(spacing: 12) {
                AmountBar(side: .income, amount: totals.income, largest: largest)
                AmountBar(side: .spent, amount: totals.spent, largest: largest)
            }

            NavigationLink(value: ReportScreen.details(.netIncome)) {
                Text(Strings.Report.seeDetails)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What Net income counts, in one sentence.
    static let explanation = String(
        localized: Strings.Report.netIncomeExplanation
    )
}

/// One side's amount as a bar in its color, labelled with the side's name and amount. `largest` is the bar that fills
/// the width, the larger of the two sides' amounts.
private struct AmountBar: View {
    let side: SpentOrIncome
    let amount: Money
    let largest: Int

    var body: some View {
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
                    .frame(width: proxy.size.width * fraction)
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// The share of the width the bar fills: the whole of it for the larger side, and in proportion for the other.
    private var fraction: Double {
        guard largest > 0 else { return 0 }
        return min(max(Double(amount.cents) / Double(largest), 0), 1)
    }
}
