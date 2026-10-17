import SwiftUI

/// The Report's Category report card: Income and Spent side by side, each with its total for the period and, under it,
/// a donut of that side's parent categories.
struct CategoryReportCard: View {
    let income: CategoryBreakdown
    let spent: CategoryBreakdown

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile(income)
            tile(spent)
        }
        .padding(.vertical, 4)
    }

    /// One side: its name and total, in its color, over its donut.
    private func tile(_ breakdown: CategoryBreakdown) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 2) {
                Text(breakdown.side.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(breakdown.total.formatted())
                    .font(.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(breakdown.side.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            CategoryDonut(breakdown: breakdown)
        }
        .frame(maxWidth: .infinity)
    }
}
