import SwiftData
import SwiftUI

/// Deletes a transaction after asking how: a plain confirmation for a transaction on its own, or whether to
/// delete its related transactions too. Every delete goes through ``Transaction/delete(_:in:)``.
struct TransactionDeleteButton: View {
    let transaction: Transaction
    /// Called once the transaction is gone, so the screen showing it can close.
    var didDelete: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var prompt: TransactionDeletePrompt?
    @State private var errorMessage: String?

    var body: some View {
        Button("Delete Transaction", systemImage: "trash", role: .destructive) {
            do {
                prompt = try TransactionDeletePrompt(for: [transaction], in: context)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .foregroundStyle(.red)
        .transactionDeleteDialog($prompt, didDelete: didDelete)
        .errorAlert("Couldn't Delete Transaction", message: $errorMessage)
    }
}

/// What the user is asked before deleting one or more transactions: a plain confirmation when no link would break,
/// otherwise whether to delete the related transactions left out too.
struct TransactionDeletePrompt {
    let transactions: [Transaction]
    /// How many transactions are linked to ``transactions`` without being among them.
    let relatedCount: Int
    /// The answers offered, the default first.
    let scopes: [TransactionDeleteScope]

    init(for transactions: [Transaction], in context: ModelContext) throws {
        self.transactions = transactions
        relatedCount = try transactions.related(in: context).count
        scopes = try transactions.deleteScopes(in: context)
    }

    var title: String {
        if relatedCount > 0 { return String(localized: "Delete the related transactions too?") }
        return transactions.count == 1
            ? String(localized: "Delete this transaction?")
            : String(localized: "Delete \(transactions.count) transactions?")
    }

    var message: String? {
        guard relatedCount > 0 else { return nil }
        return transactions.count == 1
            ? String(localized: "This transaction has \(relatedCount) related transactions.")
            : String(localized: "The selected transactions have \(relatedCount) related transactions that aren't selected.")
    }

    func buttonTitle(for scope: TransactionDeleteScope) -> String {
        scope.buttonTitle(selectedCount: transactions.count, relatedCount: relatedCount)
    }
}

extension View {
    /// Asks how to delete the transactions of `prompt` while it is set, then deletes them through
    /// ``Swift/Collection/delete(_:in:)`` and calls `didDelete`.
    func transactionDeleteDialog(
        _ prompt: Binding<TransactionDeletePrompt?>,
        didDelete: @escaping () -> Void
    ) -> some View {
        modifier(TransactionDeleteDialog(prompt: prompt, didDelete: didDelete))
    }
}

private struct TransactionDeleteDialog: ViewModifier {
    @Binding var prompt: TransactionDeletePrompt?
    let didDelete: () -> Void

    @Environment(\.modelContext) private var context
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                prompt?.title ?? "",
                isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }),
                titleVisibility: .visible,
                presenting: prompt
            ) { prompt in
                ForEach(prompt.scopes, id: \.self) { scope in
                    Button(prompt.buttonTitle(for: scope), role: .destructive) {
                        delete(prompt.transactions, scope)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { prompt in
                if let message = prompt.message {
                    Text(message)
                }
            }
            .errorAlert("Couldn't Delete Transaction", message: $errorMessage)
    }

    private func delete(_ transactions: [Transaction], _ scope: TransactionDeleteScope) {
        do {
            try transactions.delete(scope, in: context)
            didDelete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension TransactionDeleteScope {
    /// The button that picks this answer when deleting `selectedCount` transactions that have `relatedCount`
    /// related transactions left out of them.
    func buttonTitle(selectedCount: Int = 1, relatedCount: Int) -> String {
        switch self {
        case .onlyThisOne where selectedCount == 1:
            relatedCount > 0 ? String(localized: "Only This One") : String(localized: "Delete Transaction")
        case .onlyThisOne:
            relatedCount > 0
                ? String(localized: "Only These \(selectedCount)")
                : String(localized: "Delete \(selectedCount) Transactions")
        case .withRelated:
            selectedCount + relatedCount == 2
                ? String(localized: "Delete Both")
                : String(localized: "Delete All \(selectedCount + relatedCount)")
        }
    }
}
