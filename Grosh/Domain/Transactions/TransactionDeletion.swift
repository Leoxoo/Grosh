import SwiftData

/// What goes when the user deletes transactions that have related transactions.
nonisolated enum TransactionDeleteScope: Hashable, Sendable {
    /// Just the transactions the user chose; the transactions linked to them stay.
    case onlyThisOne
    /// The chosen transactions and every transaction linked to them.
    case withRelated
}

extension Transaction {
    /// What the user is asked to choose between when deleting this transaction, the default first. A transaction
    /// with nothing related is simply deleted; one with related transactions offers to delete them too, so a link
    /// is never broken silently.
    func deleteScopes(in context: ModelContext) throws -> [TransactionDeleteScope] {
        try [self].deleteScopes(in: context)
    }

    /// Deletes this transaction, and its related transactions too for `.withRelated`. Saves, so every balance
    /// stops counting it straight away.
    func delete(_ scope: TransactionDeleteScope, in context: ModelContext) throws {
        try [self].delete(scope, in: context)
    }
}

extension Collection where Element == Transaction {
    /// The transactions linked to these ones that aren't among them: the links deleting only these would break.
    /// Listed newest first.
    func related(in context: ModelContext) throws -> [Transaction] {
        let chosen = Set(map(\.persistentModelID))
        var seen = Set<PersistentIdentifier>()
        var related: [Transaction] = []
        for transaction in self {
            for other in try transaction.related(in: context)
            where !chosen.contains(other.persistentModelID) && seen.insert(other.persistentModelID).inserted {
                related.append(other)
            }
        }
        return related.inListOrder()
    }

    /// What the user is asked to choose between when deleting these transactions, the default first: a plain
    /// delete when no link would break, otherwise whether to delete the related transactions too.
    func deleteScopes(in context: ModelContext) throws -> [TransactionDeleteScope] {
        try related(in: context).isEmpty ? [.onlyThisOne] : [.withRelated, .onlyThisOne]
    }

    /// The one way transactions are deleted, one from its detail screen or several selected in the list. Saves,
    /// so every balance stops counting them straight away.
    func delete(_ scope: TransactionDeleteScope, in context: ModelContext) throws {
        if scope == .withRelated {
            for transaction in try related(in: context) {
                context.delete(transaction)
            }
        }
        for transaction in self {
            context.delete(transaction)
        }
        try context.save()
    }
}
