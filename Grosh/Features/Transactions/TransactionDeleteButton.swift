import SwiftData
import SwiftUI

/// Deletes a transaction after asking how: a plain confirmation for a transaction on its own, or whether to
/// delete its related transactions too. Every delete goes through ``Transaction/delete(_:in:)``.
struct TransactionDeleteButton: View {
    let transaction: Transaction
    /// Called once the transaction is gone, so the screen showing it can close.
    var didDelete: () -> Void = {}

    @Environment(\.modelContext) private var context
    @State private var scopes: [TransactionDeleteScope] = []
    @State private var relatedCount = 0
    @State private var isConfirming = false
    @State private var errorMessage: String?

    var body: some View {
        Button("Delete Transaction", systemImage: "trash", role: .destructive) {
            do {
                scopes = try transaction.deleteScopes(in: context)
                relatedCount = try transaction.related(in: context).count
                isConfirming = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .foregroundStyle(.red)
        .confirmationDialog(title, isPresented: $isConfirming, titleVisibility: .visible) {
            ForEach(scopes, id: \.self) { scope in
                Button(scope.buttonTitle(relatedCount: relatedCount), role: .destructive) {
                    delete(scope)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if relatedCount > 0 {
                Text("This transaction has \(relatedCount) related transactions.")
            }
        }
        .alert("Couldn't Delete Transaction", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var title: String {
        relatedCount > 0
            ? String(localized: "Delete the related transactions too?")
            : String(localized: "Delete this transaction?")
    }

    private func delete(_ scope: TransactionDeleteScope) {
        do {
            try transaction.delete(scope, in: context)
            didDelete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension TransactionDeleteScope {
    /// The button that picks this answer when deleting a transaction with `relatedCount` related transactions.
    func buttonTitle(relatedCount: Int) -> String {
        switch self {
        case .onlyThisOne:
            relatedCount > 0 ? String(localized: "Only This One") : String(localized: "Delete Transaction")
        case .withRelated:
            relatedCount == 1 ? String(localized: "Delete Both") : String(localized: "Delete All \(relatedCount + 1)")
        }
    }
}
