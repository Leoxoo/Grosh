import Foundation
import SwiftData

/// The amount a varying Bill's transactions start at, before the real one is entered: the average of the most recent
/// usable transactions filed under the Bill's category.
nonisolated enum AmountEstimate {
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
        let recent = usable.inListOrder().prefix(sampleSize)
        guard !recent.isEmpty else { return nil }
        let total = recent.reduce(0) { $0 + abs($1.amountCents) }
        return Int((Double(total) / Double(recent.count)).rounded())
    }

    /// ``cents(among:for:currencyCode:)`` over what the store holds for `category`, read through its context: only
    /// the newest of its usable transactions, which the store finds and sorts, rather than every transaction filed
    /// under it. `nil` too when the store can't be read, which is logged.
    static func cents(for category: Category, currencyCode: String) -> Int? {
        guard let context = category.modelContext else { return nil }
        return Log.store.attempt("Reading a varying Bill's estimate") {
            let newest = try newestUsable(for: category, currencyCode: currencyCode, in: context)
            return cents(among: newest, for: category, currencyCode: currencyCode)
        } ?? nil
    }

    /// The ``sampleSize`` newest usable transactions filed under `category` or its subcategories in `currencyCode`, by
    /// day and by when they were entered, plus any entered at the very moment of the last of them: list order breaks
    /// that tie by identity, which the store can't sort by, so ``cents(among:for:currencyCode:)`` picks among them.
    private static func newestUsable(
        for category: Category, currencyCode: String, in context: ModelContext
    ) throws -> [Transaction] {
        let id = category.persistentModelID
        let usable = #Predicate<Transaction> { transaction in
            (transaction.category?.persistentModelID == id || transaction.category?.parent?.persistentModelID == id)
                && transaction.deletedAt == nil && !transaction.isEstimated && !transaction.isExcludedFromReport
                && transaction.wallet?.currencyCode == currencyCode
        }
        var newest = FetchDescriptor<Transaction>(
            predicate: usable,
            sortBy: [SortDescriptor(\.dayRaw, order: .reverse), SortDescriptor(\.createdAt, order: .reverse)]
        )
        newest.fetchLimit = sampleSize
        let found = try context.fetch(newest)
        guard found.count == sampleSize, let last = found.last else { return found }
        let dayRaw = last.dayRaw
        let createdAt = last.createdAt
        let tied = try context.fetch(
            FetchDescriptor<Transaction>(predicate: #Predicate { $0.dayRaw == dayRaw && $0.createdAt == createdAt })
        )
        return found + tied.filter { !found.contains($0) }
    }
}
