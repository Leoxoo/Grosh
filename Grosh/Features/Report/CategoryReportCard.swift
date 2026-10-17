import SwiftUI

/// The Report's Category report card: Spent and Income side by side, each with its total for the period and, under it,
/// a donut of that side's parent categories. Tapping a side opens its details.
struct CategoryReportCard: View {
    let income: CategoryBreakdown
    let spent: CategoryBreakdown
    /// Opens the details of a side, which the Report pushes. A tile is a button rather than a link: two links in one List row
    /// all open the last of them.
    let onOpen: (SpentOrIncome) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            tile(spent)
            tile(income)
        }
        .padding(.vertical, 4)
    }

    /// One side: its name and total, in its color, over its donut.
    private func tile(_ breakdown: CategoryBreakdown) -> some View {
        Button {
            onOpen(breakdown.side)
        } label: {
            VStack(spacing: 12) {
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(breakdown.side.title)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
