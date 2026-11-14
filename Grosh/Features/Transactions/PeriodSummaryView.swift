import SwiftUI

/// The period's Opening balance, Ending balance (the projected balance, for a period reaching past today) and their
/// difference: three figures in a row, in the Transactions tab's header under the period strip.
struct PeriodSummaryView: View {
    let summary: PeriodSummary
    let period: Period

    @Environment(\.today) private var today

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            SummaryFigure(
                title: Text(Strings.Common.openingBalance),
                value: Text(summary.openingBalance.formatted()).monospacedDigit()
            )
            SummaryFigure(
                title: Text(period.isProjected(today: today) ? Strings.Transactions.projectedBalance : Strings.Common.endingBalance),
                value: Text(summary.endingBalance.formatted()).monospacedDigit()
            )
            SummaryFigure(
                title: Text(Strings.Common.difference),
                value: AmountText(amount: summary.difference, showsPlusSign: true, showsColor: false)
            )
        }
        .padding(.horizontal)
    }
}

/// A small title over its value, both centered in an equal share of a summary row.
struct SummaryFigure<Value: View>: View {
    let title: Text
    let value: Value

    var body: some View {
        VStack(spacing: 2) {
            title
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            value
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
