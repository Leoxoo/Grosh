import Foundation
import SwiftData

/// Why a transaction can't be attached to a Recurring transaction.
nonisolated enum AttachError: Error, Equatable {
    case notAttachable
}

extension AttachError: LocalizedError {
    var errorDescription: String? {
        String(localized: "That transaction is in Recently Deleted or already belongs to a Recurring transaction.")
    }
}

extension Transaction {
    /// Whether the user can attach this transaction to a Recurring transaction: it is outside Recently Deleted and no
    /// Recurring transaction holds it yet. A transaction belongs to one schedule at a time, so attaching one that
    /// another schedule holds is refused.
    var isAttachable: Bool { deletedAt == nil && recurring == nil }

    /// Orders transactions newest first: by day, then by when each was entered.
    static func newestFirst(_ lhs: Transaction, _ rhs: Transaction) -> Bool {
        lhs.dayRaw == rhs.dayRaw ? lhs.createdAt > rhs.createdAt : lhs.dayRaw > rhs.dayRaw
    }
}

extension RecurringTransaction {
    /// Attaches an existing transaction, so the schedule lists it with the transactions it made. Only the link changes:
    /// the schedule and the occurrences still to come stay as they are. Throws `AttachError.notAttachable` for a
    /// transaction that isn't attachable, so nothing is moved. Saves.
    func attach(_ transaction: Transaction, in context: ModelContext) throws {
        guard transaction.isAttachable else { throw AttachError.notAttachable }
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
