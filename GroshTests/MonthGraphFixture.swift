import SwiftData
import Testing
@testable import Grosh

/// An in-memory store seeded with the default category tree and a Checking wallet, for Month graph tests. It is seen on
/// `today`, the 12th of a 31-day October, after a 30-day September and a year after another 31-day October.
@MainActor
struct MonthGraphFixture {
    let today = day(2026, 10, 12)
    private let categories: CategoryFixture
    var context: ModelContext { categories.context }
    var checking: Wallet { categories.wallet }

    init() throws {
        categories = try CategoryFixture()
    }

    func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try categories.category(name, type)
    }

    /// Records `cents` (signed, as it moves the wallet) filed under `categoryName` on `day`, in Checking unless another
    /// wallet is given.
    @discardableResult
    func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay,
        in wallet: Wallet? = nil
    ) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet ?? checking
        transaction.category = try category(categoryName, type)
        return transaction
    }

    /// The card for `side` showing `month`, this month unless another is given, compared with `choice`, as Home makes
    /// it: from what it reads from the store for that month (``MonthGraphHistory``) and every Recurring transaction,
    /// those in Recently Deleted included. Saves first, as the app has by the time Home reads.
    func graph(
        _ side: SpentOrIncome, in month: CalendarMonth? = nil, comparingWith choice: MonthGraphComparison = .average
    ) throws -> MonthGraph {
        let month = month ?? CalendarMonth(today)
        try context.save()
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        let history = try context.fetch(MonthGraphHistory.transactions(for: month))
            + context.fetch(MonthGraphHistory.forgiven)
        return try MonthGraph(
            side, of: history, countingFrom: firstDay(), recurring: recurring, in: month, today: today,
            comparingWith: choice
        )
    }

    /// The months Home's strip offers, from what it reads from the store (``MonthGraphHistory``). Saves first.
    func strip() throws -> [Period] {
        try context.save()
        return try MonthGraph.months(from: firstDay(), today: today)
    }

    /// The first day anything counts on the Month graph, as Home reads it from the store.
    private func firstDay() throws -> CalendarDay? {
        try MonthGraphHistory.firstDay(
            earliest: context.fetch(MonthGraphHistory.earliestCounted), forgiven: context.fetch(MonthGraphHistory.forgiven)
        )
    }
}
