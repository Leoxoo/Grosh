import SwiftData
import SwiftUI

/// The transaction detail's Related transactions: every transaction sharing its link, such as the other half of
/// a transfer or the other parts of a Split, which add Undo split. Each opens its own detail. Shows nothing when
/// there are none. Use inside a `List`.
struct RelatedTransactionsSection: View {
    let transaction: Transaction

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var isConfirmingUndoSplit = false
    @State private var errorMessage: String?

    /// Every transaction sharing the link, this one included, so one linked later shows straight away.
    @Query private var linked: [Transaction]

    init(transaction: Transaction) {
        self.transaction = transaction
        _linked = Query(transaction.linkedTransactions)
    }

    var body: some View {
        let related = transaction.related(among: linked)
        if !related.isEmpty {
            Section("Related transactions") {
                ForEach(related) { other in
                    NavigationLink {
                        TransactionDetailView(transaction: other)
                    } label: {
                        RelatedTransactionRow(transaction: other)
                    }
                }
                if transaction.isSplitPart {
                    Button("Undo Split", systemImage: "arrow.uturn.backward") {
                        isConfirmingUndoSplit = true
                    }
                    .confirmationDialog(
                        "Undo this split?", isPresented: $isConfirmingUndoSplit, titleVisibility: .visible
                    ) {
                        Button("Undo Split", role: .destructive, action: undoSplit)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The parts merge back into the original, which takes the sum of their amounts.")
                    }
                    .errorAlert("Couldn't Undo Split", message: $errorMessage)
                }
            }
        }
    }

    /// Merges the split back, then leaves this transaction's detail if it was one of the parts merged away.
    private func undoSplit() {
        let id = transaction.persistentModelID
        do {
            if try transaction.undoSplit(in: context).persistentModelID != id {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A related transaction with its date, since it may fall on another day.
private struct RelatedTransactionRow: View {
    let transaction: Transaction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TransactionRow(transaction: transaction)
            Text(transaction.day.date().formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)
        }
    }
}
