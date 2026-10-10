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
        for descriptor in Self.listOrder {
            switch descriptor.compare(self, other) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: continue
            }
        }
        return persistentModelID > other.persistentModelID
    }
}

extension Sequence where Element == Transaction {
    /// The transactions in the order every transaction list shows them: newest day first and, within a day,
    /// the most recently entered first.
    func inListOrder() -> [Transaction] {
        sorted { $0.isListed(before: $1) }
    }

    /// The earliest day any of the transactions is dated, or `nil` when there are none: where a period strip of them
    /// starts.
    var firstDay: CalendarDay? {
        map(\.dayRaw).min().map(CalendarDay.init(rawValue:))
    }
}
