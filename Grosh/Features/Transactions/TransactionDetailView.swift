import SwiftData
import SwiftUI

/// One transaction with all its fields, its Related transactions, and Edit, Duplicate and Delete.
/// Use inside a `NavigationStack`.
struct TransactionDetailView: View {
    let transaction: Transaction
    /// Called once the transaction is deleted. Without it, the screen dismisses itself.
    var didDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var editorMode: TransactionEditor.Mode?

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
        .sheet(item: $editorMode) { mode in
            TransactionEditor(mode: mode)
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

            Section {
                fields
            }

            RelatedTransactionsSection(transaction: transaction)

            Section {
                if transaction.canBeDuplicated {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        editorMode = .duplicate(transaction)
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
            if transaction.editFlow == .addSheet {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editorMode = .edit(transaction) }
                }
            }
        }
    }

    /// Every other field of the transaction. Empty optional fields are left out.
    @ViewBuilder
    private var fields: some View {
        if let wallet = transaction.wallet {
            LabeledContent("Wallet") {
                HStack(spacing: 6) {
                    Image(systemName: wallet.symbolName)
                        .foregroundStyle(wallet.color.color)
                    Text(wallet.name)
                }
            }
        }
        if let card = transaction.card {
            LabeledContent("Card") {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.fill")
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
            SymbolCircle(
                symbolName: transaction.category?.symbolName ?? "questionmark",
                color: transaction.category?.color ?? .gray,
                size: 48
            )
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
