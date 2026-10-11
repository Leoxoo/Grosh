import SwiftData
import SwiftUI

/// Picks an existing transaction to attach to a Recurring transaction: any transaction in any wallet, outside Recently
/// Deleted and not held by another Recurring transaction, newest first. Tapping one attaches it and closes the picker.
struct LinkExistingTransactionView: View {
    let recurring: RecurringTransaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(Transaction.notDeleted) private var transactions: [Transaction]
    @State private var errorMessage: String?

    private var candidates: [Transaction] {
        transactions.filter(\.isAttachable).sorted(by: Transaction.newestFirst)
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Transactions to Link",
                        systemImage: "tray",
                        description: Text("Transactions that aren't attached to a Recurring transaction appear here.")
                    )
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
