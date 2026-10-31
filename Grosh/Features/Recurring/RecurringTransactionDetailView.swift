import SwiftData
import SwiftUI

/// One Recurring transaction: what it is, when it next falls due, and the transactions it has made or the user has
/// attached. A transaction opens in the normal editor. Add the Transaction makes one now, dated today, without touching
/// the schedule. Link existing attaches one from any wallet, and Unlink detaches it without deleting it. A Purchase
/// shows its progress and adds a payment in the normal editor, prefilled from it. Edit changes only what is still to
/// come. Duplicate opens a copy to edit, starting today. Delete moves the schedule to Recently Deleted and keeps what
/// it holds.
struct RecurringTransactionDetailView: View {
    let recurring: RecurringTransaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.today) private var today
    @State private var isEditing = false
    @State private var isDuplicating = false
    @State private var editingTransaction: Transaction?
    @State private var isAddingPayment = false
    @State private var isLinking = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    /// Whether the schedule was deleted from this screen. Nothing is read from it then, since a deleted model still on
    /// screen can't be read.
    private var isRemoved: Bool { recurring.isDeleted || recurring.modelContext == nil }

    var body: some View {
        if isRemoved {
            ContentUnavailableView(Strings.Recurring.deleted, systemImage: "trash")
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
                        HStack(spacing: 6) {
                            AmountText(amount: recurring.startingAmount)
                            if recurring.estimatesAmount {
                                EstimatedBadge()
                            }
                        }
                    }
                }
                LabeledContent(Strings.Common.wallet) {
                    Text(recurring.wallet?.name ?? String(localized: Strings.Common.none))
                }
                LabeledContent(Strings.Common.category) {
                    Text(recurring.category?.name ?? String(localized: Strings.Common.none))
                }
                if let card = recurring.card {
                    LabeledContent(Strings.Common.card) {
                        Text(card.name)
                    }
                }
                LabeledContent(Strings.Recurring.repeatTitle) {
                    Text(recurring.schedule.summary)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent(Strings.Recurring.next) {
                    if recurring.isPaused {
                        Text(Strings.Recurring.paused)
                    } else if let next = recurring.nextDueDay {
                        Text(next.date(), style: .date)
                    } else {
                        Text(Strings.Recurring.ended)
                    }
                }
                if let progress = recurring.purchaseProgress {
                    LabeledContent(Strings.Recurring.progress) {
                        Text(progress.summary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if !recurring.note.isEmpty {
                    LabeledContent(Strings.Common.note) {
                        Text(recurring.note)
                            .multilineTextAlignment(.trailing)
                    }
                }
            } footer: {
                if recurring.isPaused {
                    Text(Strings.Recurring.walletArchivedFooter)
                }
            }

            Section {
                Button(Strings.Recurring.addTheTransaction, systemImage: "plus.circle") {
                    addTransactionNow()
                }
                .disabled(!recurring.canAddTransactionNow)
                if recurring.kind == .purchase {
                    Button(Strings.Recurring.addAPayment, systemImage: "square.and.pencil") {
                        isAddingPayment = true
                    }
                    .disabled(!recurring.isActive)
                }
                Button(Strings.Recurring.linkExisting, systemImage: "link") {
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
                        Button(Strings.Recurring.unlink) { unlink(transaction) }
                    }
                    .contextMenu {
                        Button(Strings.Recurring.unlink) { unlink(transaction) }
                    }
                }
            } header: {
                Text(Strings.Common.transactions)
            } footer: {
                if recurring.attachedTransactions.isEmpty {
                    Text(Strings.Recurring.transactionsFooter)
                }
            }

            Section {
                Button(Strings.Common.duplicate, systemImage: "doc.on.doc") {
                    isDuplicating = true
                }
            }

            Section {
                Button(Strings.Recurring.deleteRecurring, systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .foregroundStyle(.destructive)
            }
        }
        .navigationTitle(recurring.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Common.edit) { isEditing = true }
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
        .sheet(isPresented: $isAddingPayment) {
            TransactionEditor(mode: .payment(recurring))
        }
        .sheet(isPresented: $isDuplicating) {
            RecurringTransactionEditor(mode: .duplicate(recurring))
        }
        .confirmationDialog(
            Strings.Recurring.deleteQuestion,
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button(Strings.Recurring.deleteRecurring, role: .destructive) { delete() }
            Button(Strings.Common.cancel, role: .cancel) {}
        } message: {
            Text(Strings.Recurring.deleteMessage(RecentlyDeleted.keptDays))
        }
        .errorAlert(Strings.Recurring.couldntChange, message: $errorMessage)
    }

    private func addTransactionNow() {
        do {
            try recurring.addTransactionNow(today: today, in: context)
        } catch {
            Log.recurring.failed("Adding a transaction now", error)
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try recurring.delete(today: today, in: context)
            dismiss()
        } catch {
            Log.recurring.failed("Deleting a Recurring transaction", error)
            errorMessage = error.localizedDescription
        }
    }

    private func unlink(_ transaction: Transaction) {
        do {
            try recurring.unlink(transaction, in: context)
        } catch {
            Log.recurring.failed("Unlinking a transaction", error)
            errorMessage = error.localizedDescription
        }
    }
}
