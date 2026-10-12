import SwiftData
import SwiftUI

/// Picks an existing transaction to attach to a Recurring transaction: any transaction in any wallet, outside Recently
/// Deleted and not held by another Recurring transaction, newest first. The filters open on the schedule's wallet and
/// category, and the user can change or clear them. Tapping one attaches it and closes the picker.
struct LinkExistingTransactionView: View {
    let recurring: RecurringTransaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    @State private var filter: TransactionFilter
    @State private var errorMessage: String?

    init(recurring: RecurringTransaction) {
        self.recurring = recurring
        _filter = State(initialValue: recurring.linkPickerFilter)
    }

    private var candidates: [Transaction] {
        transactions.filter(\.isAttachable).matching(filter).inListOrder()
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    if filter.isOn {
                        NoMatchingTransactionsView(filter: filter)
                    } else {
                        ContentUnavailableView(
                            "No Transactions to Link",
                            systemImage: "tray",
                            description: Text("Transactions that no Recurring transaction holds appear here.")
                        )
                    }
                } else {
                    List(candidates) { transaction in
                        Button {
                            attach(transaction)
                        } label: {
                            TransactionRow(transaction: transaction, showsDay: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Link Transaction")
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
            .errorAlert("Couldn't Link Transaction", message: $errorMessage)
        }
    }

    private func attach(_ transaction: Transaction) {
        do {
            try recurring.attach(transaction, in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
