import SwiftData
import SwiftUI

/// Income or Spent details: the period's total for the side and its Daily average, a donut of the side's parent categories,
/// and every parent category largest first with its share. Tapping a category lists its transactions in the period. It
/// shares the Report's wallet selection, time range and period.
struct SideDetailsView: View {
    let side: SpentOrIncome
    @Binding var walletSelection: WalletSelection
    @Binding var timeRange: TimeRange
    @Binding var period: Period

    @Query(Transaction.notDeleted) private var transactions: [Transaction]

    var body: some View {
        let today = CalendarDay.today
        let days = transactions.reportDays(of: period, in: walletSelection, today: today)
        let counted = transactions.counted(in: walletSelection, during: period, today: today)
        let totals = PeriodTotals(of: counted)
        let total = side == .income ? totals.income : totals.spent
        let breakdown = CategoryBreakdown(side: side, of: counted)
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Total")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(total.formatted())
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                        .foregroundStyle(side.color)
                        .contentTransition(.numericText())
                    if timeRange != .day, let average = DailyAverage.of(total, over: days) {
                        LabeledContent("Daily average") {
                            Text(average.formatted()).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                CategoryDonut(breakdown: breakdown)
                    .frame(maxWidth: 240)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            Section {
                ForEach(breakdown.categories, id: \.category) { row in
                    NavigationLink(
                        value: ReportScreen.category(side, row.category, days: days, walletSelection: walletSelection)
                    ) {
                        CategoryBreakdownRow(
                            category: row.category, total: row.total, share: breakdown.share(of: row.total)
                        )
                    }
                }
            }
        }
        .roundedSectionsListStyle()
        .reportPeriodControls(
            walletSelection: $walletSelection, timeRange: $timeRange, period: $period, transactions: transactions,
            showsWalletSelector: false
        )
        .navigationTitle(side.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// A parent category's icon and name, its amount, and its share of the side, as a row of the Breakdown.
private struct CategoryBreakdownRow: View {
    let category: Category
    let total: Money
    let share: Double

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 32)
            Text(category.name)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(total.formatted())
                    .monospacedDigit()
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
