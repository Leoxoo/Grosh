import SwiftData
import SwiftUI

/// The transactions that count in one Step of a Net income or Trend row: all of them for Net income, or those toward one
/// side for a Trend row, by day newest first under the Step's total. There is no breakdown: this is the period's list.
struct StepTransactionsView: View {
    /// The side listed, or `nil` to list both sides and total Net income.
    let side: SpentOrIncome?
    let title: String
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
        let listed = PeriodTransactions(
            side: side, of: transactions, in: walletSelection, days: days, otherIncome: otherIncome
        )
        List {
            Section {
                HStack {
                    Text(side?.title ?? String(localized: "Net income"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(listed.total.formatted())
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(side?.color ?? listed.total.tint)
                }
            }

            if listed.transactions.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Transactions",
                        systemImage: "tray",
                        description: Text("Nothing was recorded in this period.")
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
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
