import SwiftData
import SwiftUI

/// Picks an existing deposit to move into an Expense as a Reimbursement: any money that came in, in any wallet, outside
/// Recently Deleted, newest first. Tapping one makes its amount, day and note an entry on the Expense, sends it to
/// Recently Deleted, and closes the picker.
struct ReimbursementMoveInPicker: View {
    /// The Expense that was paid back.
    let expense: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var filter = TransactionFilter()
    @State private var errorMessage: String?

    private var candidates: [Transaction] {
        transactions.filter(\.canBeMovedIntoReimbursement).matching(filter).inListOrder()
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    if filter.isOn {
                        NoMatchingTransactionsView(filter: filter)
                    } else {
                        ContentUnavailableView(
                            "No Transactions to Move In",
                            systemImage: "tray",
                            description: Text("Money that came in, such as a deposit, appears here.")
                        )
                    }
                } else {
                    List(candidates) { transaction in
                        Button {
                            moveIn(transaction)
                        } label: {
                            TransactionRow(
                                transaction: transaction, showsDay: true, showsWalletIcon: filter.wallet == nil
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Move Transaction In")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $filter.searchText, prompt: "Note, category or amount")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    TransactionFilterButton(filter: $filter)
                }
            }
            .errorAlert("Couldn't Move Transaction In", message: $errorMessage)
        }
    }

    private func moveIn(_ deposit: Transaction) {
        do {
            try Reimbursement.moveIn(deposit, to: expense, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
