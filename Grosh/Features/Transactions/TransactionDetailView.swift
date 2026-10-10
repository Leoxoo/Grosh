import SwiftData
import SwiftUI

/// One transaction with all its fields, its Related transactions, and Edit, Duplicate and Delete.
/// Use inside a `NavigationStack`.
struct TransactionDetailView: View {
    let transaction: Transaction
    /// Called once the transaction is deleted. Without it, the screen dismisses itself.
    var didDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    /// The editor Edit opened, while it is open.
    @State private var editing: TransactionEditFlow?
    @State private var isDuplicating = false

    var body: some View {
        Group {
            if transaction.isDeleted || transaction.modelContext == nil {
                ContentUnavailableView("Transaction Deleted", systemImage: "trash")
            } else {
                details
            }
        }
        .navigationTitle("Transaction")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { flow in
            switch flow {
            case .addSheet: TransactionEditor(mode: .edit(transaction))
            case .startingBalance: StartingBalanceEditor(transaction: transaction)
            case .transferHalf: TransferHalfEditor(transaction: transaction)
            }
        }
        .sheet(isPresented: $isDuplicating) {
            TransactionEditor(mode: .duplicate(transaction))
        }
    }

    private var details: some View {
        List {
            Section {
                TransactionDetailHeader(transaction: transaction)
            }

            if transaction.isExcludedFromReport {
                Section {
                    ExcludedFromReportBanner()
                }
            }

            BalanceChangeSection(transaction: transaction)

            Section {
                fields
            }

            RelatedTransactionsSection(transaction: transaction)

            Section {
                if transaction.canBeDuplicated {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        isDuplicating = true
                    }
                }
                TransactionDeleteButton(transaction: transaction) {
                    if let didDelete { didDelete() } else { dismiss() }
                }
            } footer: {
                if transaction.canBeDuplicated {
                    Text("Duplicate opens a new transaction with the same details, dated today.")
                }
            }
        }
        .toolbar {
            if let editFlow = transaction.editFlow {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = editFlow }
                }
            }
        }
    }

    /// Every other field of the transaction. Empty optional fields are left out.
    @ViewBuilder
    private var fields: some View {
        if let wallet = transaction.wallet {
            WalletLabel(title: "Wallet", wallet: wallet)
        }
        if let card = transaction.card {
            LabeledContent("Card") {
                HStack(spacing: 6) {
                    Image(systemName: Card.symbolName)
                        .foregroundStyle(card.color.color)
                    Text(card.displayName)
                }
            }
        }
        if !transaction.note.isEmpty {
            LabeledContent("Note", value: transaction.note)
        }
        if !transaction.withName.isEmpty {
            LabeledContent("With", value: transaction.withName)
        }
        if !transaction.eventName.isEmpty {
            LabeledContent("Event", value: transaction.eventName)
        }
    }
}

/// The category, the amount in color, and the date.
private struct TransactionDetailHeader: View {
    let transaction: Transaction

    var body: some View {
        HStack(spacing: 16) {
            CategoryIcon(category: transaction.category, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.categoryName)
                    .font(.headline)
                AmountText(amount: transaction.amount)
                    .font(.title.bold())
                Text(transaction.day.date().formatted(date: .complete, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Says the transaction is left out of income and spending, but still in its wallet's balance.
private struct ExcludedFromReportBanner: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Excluded from report")
                    .font(.headline)
                Text("Left out of income and spending. It still counts in the wallet's balance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "eye.slash")
                .foregroundStyle(.orange)
        }
    }
}

extension TransactionEditFlow: Identifiable {
    var id: Self { self }
}
