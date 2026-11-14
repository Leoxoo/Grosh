import Foundation
import SwiftData

/// What a Card paid in its current period, per Reward category: what its top-spend rate is earned on.
enum CardTopSpend {
    /// The Card's Expenses outside Recently Deleted in the period containing `today` (its statement period, or the
    /// calendar month when it has no Statement date), summed per Reward category, in cents. One fetch, narrowed to the
    /// Card and the period.
    static func spending(of card: Card, on today: CalendarDay, in context: ModelContext) throws -> [String: Int] {
        let period = card.period(containing: today)
        return spending(of: try context.fetch(read(of: card, on: today)), in: period)
    }

    /// The fetch ``spending(of:on:in:)`` makes, for a screen that reads it with a query: the Card's transactions outside
    /// Recently Deleted on its current period's days.
    static func read(of card: Card, on today: CalendarDay) -> FetchDescriptor<Transaction> {
        let id = card.persistentModelID
        let period = card.period(containing: today)
        let first = period.firstDay.rawValue, last = period.lastDay.rawValue
        return FetchDescriptor(predicate: #Predicate { transaction in
            transaction.card?.persistentModelID == id && transaction.deletedAt == nil
                && transaction.dayRaw >= first && transaction.dayRaw <= last
        })
    }

    /// The Expenses among `paid` on `period`'s days, summed per Reward category, in cents.
    static func spending(of paid: [Transaction], in period: CardPeriod) -> [String: Int] {
        var spending: [String: Int] = [:]
        for transaction in paid where period.contains(transaction.day) && transaction.amountCents < 0 {
            guard let reward = transaction.category?.rewardsAs else { continue }
            spending[reward, default: 0] -= transaction.amountCents
        }
        return spending
    }

    /// ``spending(of:on:in:)``, or none when the store can't be read, which is logged: the Card then earns as though
    /// nothing was spent yet.
    static func spendingOrNone(of card: Card, on today: CalendarDay, in context: ModelContext) -> [String: Int] {
        Log.store.attempt("Reading a Card's spending this period") { try spending(of: card, on: today, in: context) } ?? [:]
    }
}
