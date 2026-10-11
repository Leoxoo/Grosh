import SwiftData
import SwiftUI

/// One Recurring transaction: what it is, when it next falls due, and the transactions it has made. A transaction
/// opens in the normal editor. Edit changes only what is still to come. Delete removes the schedule and keeps what
/// it made.
struct RecurringTransactionDetailView: View {
    let recurring: RecurringTransaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isEditing = false
    @State private var editingTransaction: Transaction?
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(category: recurring.category, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recurring.name)
                            .font(.title3.weight(.semibold))
                        AmountText(amount: recurring.signedAmount)
                    }
                }
                LabeledContent("Wallet") {
                    Text(recurring.wallet?.name ?? String(localized: "None"))
                }
                LabeledContent("Category") {
                    Text(recurring.category?.name ?? String(localized: "None"))
                }
                if let card = recurring.card {
                    LabeledContent("Card") {
                        Text(card.name)
                    }
                }
                LabeledContent("Repeat") {
                    Text(recurring.schedule.summary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Next") {
                    if let next = recurring.nextDueDay {
                        Text(next.date(), style: .date)
                    } else {
                        Text("Ended")
                    }
                }
                if !recurring.note.isEmpty {
                    LabeledContent("Note") {
                        Text(recurring.note)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section {
                ForEach(recurring.attachedTransactions) { transaction in
                    Button {
                        editingTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction, showsDay: true)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Transactions")
            } footer: {
                if recurring.attachedTransactions.isEmpty {
                    Text("The transactions it makes appear here, on their due days.")
                }
            }

            Section {
                Button("Delete Recurring Transaction", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle(recurring.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            RecurringTransactionEditor(mode: .edit(recurring))
        }
        .sheet(item: $editingTransaction) { transaction in
            TransactionEditor(mode: .edit(transaction))
        }
        .confirmationDialog(
            "Delete this recurring transaction?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Recurring Transaction", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The transactions it made stay in your wallets.")
        }
        .errorAlert("Couldn't Delete Recurring Transaction", message: $errorMessage)
    }

    private func delete() {
        do {
            try recurring.delete(in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
