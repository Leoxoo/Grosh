import SwiftUI

/// The period's Opening balance, Ending balance (the projected balance, for a period reaching past today) and their
/// difference: three figures in a row, in the Transactions tab's header under the period strip.
struct PeriodSummaryView: View {
    let summary: PeriodSummary
    let period: Period
    var today: CalendarDay = .today

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            figure("Opening balance") {
                Text(summary.openingBalance.formatted())
                    .monospacedDigit()
            }
            figure(period.isProjected(today: today) ? "Projected balance" : "Ending balance") {
                Text(summary.endingBalance.formatted())
                    .monospacedDigit()
            }
            figure("Difference") {
                AmountText(amount: summary.difference, showsPlusSign: true)
            }
        }
        .padding(.horizontal)
    }

    /// A small label over its value, both centered in an equal share of the row.
    private func figure(_ title: LocalizedStringKey, @ViewBuilder value: () -> some View) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            value()
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
