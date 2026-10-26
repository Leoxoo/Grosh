import Foundation
import SwiftData

extension Transaction {
    /// The order every transaction list shows: newest day first and, within a day, the most recently entered
    /// first. Store fetches sort by it; ``isListed(before:)`` adds the tie-break a fetch can't express.
    static let listOrder: [SortDescriptor<Transaction>] = [
        SortDescriptor(\.dayRaw, order: .reverse),
        SortDescriptor(\.createdAt, order: .reverse),
    ]

    /// Whether `self` is listed above `other` in ``listOrder``. Transactions entered at the same moment (as an
    /// import does) fall back to their saved identity, so their order never depends on the order the store hands
    /// them back in.
    func isListed(before other: Transaction) -> Bool {
        ListPosition(self).isListed(before: ListPosition(other))
    }
}

/// What ``Transaction/listOrder`` sorts a transaction by, read once: a model's stored properties are slow to read, and
/// a sort reads them for every comparison.
nonisolated private struct ListPosition {
    let dayRaw: Int
    let createdAt: Date
    let transaction: Transaction

    init(_ transaction: Transaction) {
        dayRaw = transaction.dayRaw
        createdAt = transaction.createdAt
        self.transaction = transaction
    }

    /// Newest day first, then the most recently entered, then by saved identity, as ``Transaction/listOrder`` and
    /// ``Transaction/isListed(before:)`` have it.
    func isListed(before other: ListPosition) -> Bool {
        if dayRaw != other.dayRaw { return dayRaw > other.dayRaw }
        if createdAt != other.createdAt { return createdAt > other.createdAt }
        return transaction.persistentModelID > other.transaction.persistentModelID
    }
}

nonisolated extension Sequence where Element == Transaction {
    /// The transactions in the order every transaction list shows them: newest day first and, within a day,
    /// the most recently entered first.
    func inListOrder() -> [Transaction] {
        map(ListPosition.init).sorted { $0.isListed(before: $1) }.map(\.transaction)
    }
}
