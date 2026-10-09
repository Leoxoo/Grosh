import Foundation
import SwiftData

extension Transaction {
    /// Home's Recent transactions: the latest `limit` transactions dated `today` or earlier, in ``listOrder``.
    /// Future transactions wait until their day. Show the result with ``Swift/Sequence/inListOrder()`` so
    /// transactions entered at the same moment keep a stable order.
    static func recent(limit: Int, asOf today: CalendarDay) -> FetchDescriptor<Transaction> {
        let todayRaw = today.rawValue
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.dayRaw <= todayRaw },
            sortBy: listOrder
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
