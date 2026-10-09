import Foundation
import SwiftData

extension Transaction {
    /// Whether `self` is listed above `other`: newer days first and, within a day, the most recently entered first.
    /// Transactions entered at the same moment (as an import does) fall back to their saved identity, so their
    /// order never depends on the order the store hands them back in.
    func isListed(before other: Transaction) -> Bool {
        if dayRaw != other.dayRaw { return dayRaw > other.dayRaw }
        if createdAt != other.createdAt { return createdAt > other.createdAt }
        return persistentModelID > other.persistentModelID
    }
}

extension Sequence where Element == Transaction {
    /// The transactions in the order every transaction list shows them: newest day first and, within a day,
    /// the most recently entered first.
    func inListOrder() -> [Transaction] {
        sorted { $0.isListed(before: $1) }
    }
}
