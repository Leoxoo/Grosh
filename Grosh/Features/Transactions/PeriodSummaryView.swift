import SwiftUI

/// The period's Opening balance, Ending balance (the projected balance, for a period reaching past today) and
/// their difference. Use inside a `List` section.
struct PeriodSummaryView: View {
    let summary: PeriodSummary
    let period: Period
    var today: CalendarDay = .today

    var body: some View {
        LabeledContent("Opening balance") {
            Text(summary.openingBalance.formatted())
                .monospacedDigit()
        }
        LabeledContent(period.isProjected(today: today) ? "Projected balance" : "Ending balance") {
            Text(summary.endingBalance.formatted())
                .monospacedDigit()
        }
        LabeledContent("Difference") {
            AmountText(amount: summary.difference, showsPlusSign: true)
                .fontWeight(.semibold)
        }
    }
}
