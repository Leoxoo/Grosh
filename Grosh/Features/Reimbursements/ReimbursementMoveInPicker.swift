import SwiftData
import SwiftUI

/// Picks an existing deposit to move into an Expense as a Reimbursement: money that came into the Expense's own wallet,
/// outside Recently Deleted, newest first (``Transaction/reimbursementMoveInBlocker(into:loanOrDebtLinks:)``). Tapping
/// one makes its amount, day and note an entry on the Expense, sends it to Recently Deleted, and closes the picker.
struct ReimbursementMoveInPicker: View {
    /// The Expense that was paid back.
    let expense: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @NotDeletedTransactions private var transactions: [Transaction]
    @State private var filter = TransactionFilter()
    @State private var errorMessage: String?

    private var candidates: [Transaction] {
        // Read once for the whole list, rather than once for each linked Income in it.
        let loanOrDebtLinks = (try? Transaction.loanOrDebtLinks(in: context)) ?? []
        return transactions
            .filter { $0.canBeMovedIntoReimbursement(of: expense, loanOrDebtLinks: loanOrDebtLinks) }
            .matching(filter)
            .inListOrder()
    }

    var body: some View {
        let candidates = candidates
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    if filter.isOn {
                        NoMatchingTransactionsView(filter: filter)
                    } else {
                        ContentUnavailableView(
                            "No Transactions to Move In",
                            systemImage: "tray",
                            description: Text("Money that came into this wallet, such as a deposit, appears here.")
                        )
                    }
                } else {
                    List(candidates) { transaction in
                        Button {
                            moveIn(transaction)
                        } label: {
                            TransactionRow(transaction: transaction, showsDay: true, showsWalletIcon: false)
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
