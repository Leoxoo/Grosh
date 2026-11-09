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
            Section(Strings.Transactions.relatedTransactions) {
                ForEach(related) { other in
                    NavigationLink {
                        TransactionDetailView(transaction: other)
                    } label: {
                        // With its day, since it may fall on another.
                        TransactionRow(transaction: other, showsDay: true)
                    }
                }
                if transaction.isSplitPart {
                    Button(Strings.Transactions.undoSplit, systemImage: "arrow.uturn.backward") {
                        isConfirmingUndoSplit = true
                    }
                    .confirmationDialog(
                        Strings.Transactions.undoSplitQuestion, isPresented: $isConfirmingUndoSplit, titleVisibility: .visible
                    ) {
                        Button(Strings.Transactions.undoSplit, role: .destructive, action: undoSplit)
                        Button(Strings.Common.cancel, role: .cancel) {}
                    } message: {
                        Text(Strings.Transactions.undoSplitMessage)
                    }
                    .errorAlert(Strings.Transactions.couldntUndoSplit, message: $errorMessage)
                }
            }
        }
    }

    /// Merges the split back, then leaves this transaction's detail if it was one of the parts merged away.
    private func undoSplit() {
        let id = transaction.persistentModelID
        Log.store.perform("Undoing a split", errorMessage: &errorMessage) {
            if try transaction.undoSplit(in: context).persistentModelID != id {
                dismiss()
            }
        }
    }
}
