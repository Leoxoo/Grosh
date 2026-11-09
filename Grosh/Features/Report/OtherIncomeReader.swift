import SwiftData
import SwiftUI

/// Draws `content` with the Other Income category, read from the store once for the whole screen: the Month graph and
/// the Report count the extra of an Expense paid back beyond its amount under it
/// (``Transaction/countedAmount(in:otherIncome:)``). Should the category be missing, it says so instead.
struct OtherIncomeReader<Content: View>: View {
    @ViewBuilder let content: (Category) -> Content

    @Environment(\.modelContext) private var context

    var body: some View {
        switch Result(catching: { try context.otherCategory(.income) }) {
        case .success(let otherIncome):
            content(otherIncome)
        case .failure(let error):
            ContentUnavailableView(
                Strings.Report.cantCountIncome,
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        }
    }
}

/// Draws a Report screen's `content` with what counts for `selection` (``CountedHistory``), worked out once for the
/// screen from every transaction outside Recently Deleted.
struct CountedHistoryReader<Content: View>: View {
    let selection: WalletSelection
    @ViewBuilder let content: (CountedHistory) -> Content

    @NotDeletedTransactions private var transactions: [Transaction]

    var body: some View {
        OtherIncomeReader { otherIncome in
            content(CountedHistory(transactions, in: selection, otherIncome: otherIncome))
        }
    }
}
