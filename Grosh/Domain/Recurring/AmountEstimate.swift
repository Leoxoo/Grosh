import Foundation
import SwiftData

/// The amount a varying Bill's transactions start at, before the real one is entered: the average of the most recent
/// usable transactions filed under the Bill's category.
nonisolated enum AmountEstimate {
    /// How many of the most recent usable transactions the average is taken over.
    static let sampleSize = 12

    /// The average size in cents of the last ``sampleSize`` usable transactions filed under `category` or its
    /// subcategories, across every wallet in `currencyCode`, or `nil` when there are none or the store can't be read,
    /// which is logged. A transaction is usable when it isn't Estimated, isn't excluded from report and isn't in
    /// Recently Deleted. Nothing is converted. Only the newest usable transactions are read, which the store finds and
    /// sorts, rather than every transaction filed under the category.
    static func cents(for category: Category, currencyCode: String) -> Int? {
        guard let context = category.modelContext else { return nil }
        return Log.store.attempt("Reading a varying Bill's estimate") {
            let recent = try newestUsable(for: category, currencyCode: currencyCode, in: context)
                .inListOrder().prefix(sampleSize)
            guard !recent.isEmpty else { return nil }
            let total = recent.reduce(0) { $0 + abs($1.amountCents) }
            return Int((Double(total) / Double(recent.count)).rounded())
        } ?? nil
    }

    /// Reads the estimate `draft` needs now (``RecurringDraft/neededEstimate``) from the store, if it needs one, and
    /// gives it to the draft: what the Recurring editor does when it opens and whenever what the estimate is for changes.
    @MainActor
    static func give(to draft: inout RecurringDraft) {
        guard let request = draft.neededEstimate else { return }
        draft.setEstimate(cents(for: request.category, currencyCode: request.currencyCode), for: request)
    }

    /// The ``sampleSize`` newest usable transactions filed under `category` and under each of its subcategories in
    /// `currencyCode`, by day and by when they were entered, plus any usable ones entered at the very moment of the last
    /// of them: list order breaks that tie by identity, which the store can't sort by, so ``cents(for:currencyCode:)``
    /// picks among them. Each category is read on its own: a predicate reaching through `category?.parent` leaves out
    /// the transactions of a category that has no parent.
    private static func newestUsable(
        for category: Category, currencyCode: String, in context: ModelContext
    ) throws -> [Transaction] {
        try ([category] + (category.children ?? [])).flatMap { filed in
            try newestUsable(filedUnder: filed.persistentModelID, currencyCode: currencyCode, in: context)
        }
    }

    private static func newestUsable(
        filedUnder id: PersistentIdentifier, currencyCode: String, in context: ModelContext
    ) throws -> [Transaction] {
        let usable = #Predicate<Transaction> { transaction in
            transaction.category?.persistentModelID == id
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
        let tied = try context.fetch(FetchDescriptor<Transaction>(predicate: #Predicate { transaction in
            transaction.dayRaw == dayRaw && transaction.createdAt == createdAt && usable.evaluate(transaction)
        }))
        return found + tied.filter { !found.contains($0) }
    }
}
