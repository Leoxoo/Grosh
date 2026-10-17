import SwiftUI

/// The Report's Category report card: each side, Spent then Income, with its total for the period and, under it, a donut of
/// that side's parent categories at full width so the icons, sticks and percents have room. Tapping a side's header opens its
/// details.
struct CategoryReportCard: View {
    let income: CategoryBreakdown
    let spent: CategoryBreakdown
    /// Opens the details of a side, which the Report pushes. The header is a button rather than a link: two links in one
    /// List row all open the last of them.
    let onOpen: (SpentOrIncome) -> Void

    var body: some View {
        VStack(spacing: 28) {
            side(spent)
            side(income)
        }
        .padding(.vertical, 4)
    }

    /// One side: its name and total, in its color, which opens its details, over its donut.
    private func side(_ breakdown: CategoryBreakdown) -> some View {
        VStack(spacing: 12) {
            Button {
                onOpen(breakdown.side)
            } label: {
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
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            CategoryDonut(breakdown: breakdown)
                .frame(maxWidth: 300)
                .frame(maxWidth: .infinity)
        }
    }
}
