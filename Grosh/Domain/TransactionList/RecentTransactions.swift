import Foundation
import SwiftData

extension Transaction {
    /// Home's Recent transactions: the latest `limit` transactions dated `today` or earlier, newest day first and,
    /// within a day, the most recently entered first. Future transactions wait until their day.
    static func recent(limit: Int, asOf today: CalendarDay) -> FetchDescriptor<Transaction> {
        let todayRaw = today.rawValue
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.dayRaw <= todayRaw },
            sortBy: [SortDescriptor(\.dayRaw, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }
}
