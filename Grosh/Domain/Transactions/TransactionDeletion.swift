import SwiftData

/// What goes when the user deletes a transaction that has related transactions.
nonisolated enum TransactionDeleteScope: Hashable, Sendable {
    /// Just this transaction; the transactions linked to it stay.
    case onlyThisOne
    /// This transaction and every transaction linked to it.
    case withRelated
}

extension Transaction {
    /// What the user is asked to choose between when deleting this transaction, the default first. A transaction
    /// with nothing related is simply deleted; one with related transactions offers to delete them too, so a link
    /// is never broken silently.
    func deleteScopes(in context: ModelContext) throws -> [TransactionDeleteScope] {
        try related(in: context).isEmpty ? [.onlyThisOne] : [.withRelated, .onlyThisOne]
    }

    /// The one way a transaction is deleted, from its detail screen or anywhere else. Saves, so every balance
    /// stops counting it straight away.
    func delete(_ scope: TransactionDeleteScope, in context: ModelContext) throws {
        if scope == .withRelated {
            for transaction in try related(in: context) {
                context.delete(transaction)
            }
        }
        context.delete(self)
        try context.save()
    }
}
