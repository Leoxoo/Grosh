import Foundation
import SwiftData

/// The amount a varying Bill's transactions start at, before the real one is entered: the average of the most recent
/// usable transactions filed under the Bill's category.
enum AmountEstimate {
    /// How many of the most recent usable transactions the average is taken over.
    static let sampleSize = 12

    /// The average size in cents of the last ``sampleSize`` usable transactions filed under `category` or its
    /// subcategories, across every wallet in `currencyCode`, or `nil` when there are none. A transaction is usable when
    /// it isn't Estimated, isn't excluded from report and isn't in Recently Deleted. Nothing is converted.
    static func cents(among transactions: [Transaction], for category: Category, currencyCode: String) -> Int? {
        let filed = Set(([category] + (category.children ?? [])).map(\.persistentModelID))
        let usable = transactions.filter { transaction in
            guard let id = transaction.category?.persistentModelID, filed.contains(id) else { return false }
            return transaction.deletedAt == nil && !transaction.isEstimated && !transaction.isExcludedFromReport
                && transaction.wallet?.currencyCode == currencyCode
        }
        let recent = usable
            .sorted { lhs, rhs in lhs.dayRaw == rhs.dayRaw ? lhs.createdAt > rhs.createdAt : lhs.dayRaw > rhs.dayRaw }
            .prefix(sampleSize)
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0) { $0 + abs($1.amountCents) }
        return Int((Double(total) / Double(recent.count)).rounded())
    }
}
