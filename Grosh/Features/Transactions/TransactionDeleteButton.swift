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
        Button(Strings.Transactions.deleteTransaction, systemImage: "trash", role: .destructive) {
            do {
                prompt = try TransactionDeletePrompt(for: [transaction], in: context)
            } catch {
                Log.store.failed("Reading what deleting a transaction takes", error)
                errorMessage = error.localizedDescription
            }
        }
        .foregroundStyle(.destructive)
        .transactionDeleteDialog($prompt, didDelete: didDelete)
        .errorAlert(Strings.Transactions.couldntDelete, message: $errorMessage)
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
                Button(Strings.Common.cancel, role: .cancel) {}
            } message: { prompt in
                if let message = prompt.message {
                    Text(message)
                }
            }
            .errorAlert(Strings.Transactions.couldntDelete, message: $errorMessage)
    }

    private func delete(_ transactions: [Transaction], _ scope: TransactionDeleteScope) {
        do {
            try transactions.delete(scope, in: context)
            didDelete()
        } catch {
            Log.store.failed("Deleting a transaction", error)
            errorMessage = error.localizedDescription
        }
    }
}
