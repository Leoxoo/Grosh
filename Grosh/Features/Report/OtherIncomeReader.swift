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
                "Can't Count Income",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription)
            )
        }
    }
}
