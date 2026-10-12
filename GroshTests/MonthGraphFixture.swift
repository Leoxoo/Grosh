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

    /// Every transaction in the store, those in Recently Deleted included.
    func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    /// The card for `side` showing `month`, this month unless another is given, compared with `choice`, made from every
    /// transaction and every Recurring transaction in the store, those in Recently Deleted included.
    func graph(
        _ side: SpentOrIncome, in month: CalendarMonth? = nil, comparingWith choice: MonthGraphComparison = .average
    ) throws -> MonthGraph {
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        return try MonthGraph(
            side, of: transactions(), recurring: recurring, in: month ?? CalendarMonth(today), today: today,
            comparingWith: choice
        )
    }
}
