import SwiftData
import SwiftUI

/// The transactions of one parent category over a Breakdown row's days: those under the category and its subcategories,
/// listed by day newest first under the category's total, which is the row's amount. Tapping one opens its detail.
struct CategoryTransactionsView: View {
    let side: SpentOrIncome
    let category: Category
    let days: DayRange
    let walletSelection: WalletSelection

    @Query(Transaction.notDeleted) private var transactions: [Transaction]

    var body: some View {
        OtherIncomeReader { otherIncome in
            content(otherIncome: otherIncome)
        }
    }

    /// The list, with Other Income read once for everything it counts.
    @ViewBuilder
    private func content(otherIncome: Category) -> some View {
        let listed = CategoryTransactions(
            parent: category, side: side, of: transactions, in: walletSelection, days: days, otherIncome: otherIncome
        )
        List {
            Section {
                HStack(spacing: 8) {
                    CategoryIcon(category: category, size: 28)
                    Text(category.name)
                        .font(.headline)
                    Spacer()
                    Text(listed.total.formatted())
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(side.color)
                }
            }

            if listed.transactions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text("Nothing in this category in the period.")
                    )
                }
            }

            TransactionDaySections(transactions: listed.transactions) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
        }
        .roundedSectionsListStyle()
        .navigationTitle(category.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
