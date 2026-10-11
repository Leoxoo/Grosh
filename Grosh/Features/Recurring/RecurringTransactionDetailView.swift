import SwiftData
import SwiftUI

/// One Recurring transaction: what it is, when it next falls due, and the transactions it has made or the user has
/// attached. A transaction opens in the normal editor. Link existing attaches one from any wallet, and Unlink detaches
/// it without deleting it. Edit changes only what is still to come. Delete moves the schedule to Recently Deleted and
/// keeps what it holds.
struct RecurringTransactionDetailView: View {
    let recurring: RecurringTransaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isEditing = false
    @State private var editingTransaction: Transaction?
    @State private var isLinking = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    /// Whether the schedule was deleted from this screen. Nothing is read from it then, since a deleted model still on
    /// screen can't be read.
    private var isRemoved: Bool { recurring.isDeleted || recurring.modelContext == nil }

    var body: some View {
        if isRemoved {
            ContentUnavailableView("Recurring Transaction Deleted", systemImage: "trash")
        } else {
            details
        }
    }

    private var details: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(category: recurring.category, subscriptionIcon: recurring.subscriptionIcon, size: 44)
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
                    if recurring.isPaused {
                        Text("Paused")
                    } else if let next = recurring.nextDueDay {
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
            } footer: {
                if recurring.isPaused {
                    Text("Its wallet is archived, so it makes nothing until the wallet is unarchived.")
                }
            }

            Section {
                Button("Link existing", systemImage: "link") {
                    isLinking = true
                }
                ForEach(recurring.attachedTransactions) { transaction in
                    Button {
                        editingTransaction = transaction
                    } label: {
                        TransactionRow(transaction: transaction, showsDay: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Unlink") { unlink(transaction) }
                    }
                    .contextMenu {
                        Button("Unlink") { unlink(transaction) }
                    }
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
        .sheet(isPresented: $isLinking) {
            LinkExistingTransactionView(recurring: recurring)
        }
        .confirmationDialog(
            "Delete this recurring transaction?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Recurring Transaction", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes to Recently Deleted for \(RecentlyDeleted.keptDays) days. The transactions it made or that are attached stay in your wallets.")
        }
        .errorAlert("Couldn't Change Recurring Transaction", message: $errorMessage)
    }

    private func delete() {
        do {
            try recurring.delete(in: context)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unlink(_ transaction: Transaction) {
        do {
            try recurring.unlink(transaction, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
