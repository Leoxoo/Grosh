import Foundation
import SwiftData

extension Transaction {
    /// Whether the user can attach this transaction to a Recurring transaction: it is outside Recently Deleted and no
    /// Recurring transaction holds it yet. A transaction belongs to one schedule at a time, so one that already belongs
    /// to another is unlinked there first.
    var isAttachable: Bool { deletedAt == nil && recurring == nil }

    /// Orders transactions newest first: by day, then by when each was entered.
    static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        lhs.dayRaw == rhs.dayRaw ? lhs.createdAt > rhs.createdAt : lhs.dayRaw > rhs.dayRaw
    }
}

extension RecurringTransaction {
    /// Attaches an existing transaction, so the schedule lists it with the transactions it made. Only the link changes:
    /// the schedule and the occurrences still to come stay as they are. Saves.
    func attach(_ transaction: Transaction, in context: ModelContext) throws {
        transaction.recurring = self
        try context.save()
    }

    /// Detaches a transaction this schedule holds. It stays in its wallet as an ordinary transaction, and nothing is
    /// deleted. A transaction held by another schedule is left alone. Saves.
    func unlink(_ transaction: Transaction, in context: ModelContext) throws {
        guard transaction.recurring == self else { return }
        transaction.recurring = nil
        try context.save()
    }
}
