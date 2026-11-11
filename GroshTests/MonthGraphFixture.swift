import SwiftData
import Testing
@testable import Grosh

/// An in-memory store seeded with the default category tree and a Checking wallet, for Month graph tests. It is seen on
/// a day of its own, ``today``, the 12th of a 31-day October, after a 30-day September and a year after another 31-day
/// October; the snapshot references are drawn on it too.
@MainActor
struct MonthGraphFixture {
    let today = day(2026, 10, 12)
    private let store: TestStore
    var context: ModelContext { store.context }
    var container: ModelContainer { store.container }
    var checking: Wallet { store.checking }

    init() throws {
        store = try TestStore()
    }

    func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try store.category(name, type)
    }

    /// Records `cents` (signed, as it moves the wallet) filed under `categoryName` on `day`, in Checking unless another
    /// wallet is given.
    @discardableResult
    func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay,
        in wallet: Wallet? = nil
    ) throws -> Transaction {
        try store.record(cents, categoryName, type, on: day, in: wallet)
    }

    /// A $60 dinner under Restaurants in Checking on the 3rd of October.
    func dinner() throws -> Transaction {
        try record(-60_00, "Restaurants", on: day(2026, 10, 3))
    }

    /// A Loan (`.loan`, money lent) or Debt (`.debt`, money borrowed) of `cents` with Pasha in Checking, saved as the Add
    /// sheet's Debt/Loan tab saves it: left in the report, so only its category keeps it off the cards.
    @discardableResult
    func lendOrBorrow(_ role: LockedRole, _ cents: Int, on day: CalendarDay) throws -> Transaction {
        try context.recordLoanOrDebt(role, cents, with: context.person("Pasha"), on: day, in: checking)
    }

    /// The Other Income category, which a report reads once and counts an Expense paid back beyond its amount under.
    func otherIncome() throws -> Grosh.Category {
        try context.otherCategory(.income)
    }

    /// Every transaction in the store, those in Recently Deleted included.
    func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    /// The card for `side` showing `month`, this month unless another is given, compared with `choice`, as Home makes
    /// it: from what it reads from the store for that month (``MonthGraphHistory/read(_:in:otherIncome:)``) and every
    /// Recurring transaction, those in Recently Deleted included. Saves first, as the app has by the time Home reads.
    func graph(
        _ side: SpentOrIncome, in month: CalendarMonth? = nil, comparingWith choice: MonthGraphComparison = .average
    ) throws -> MonthGraph {
        let month = month ?? CalendarMonth(today)
        try context.save()
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        return try MonthGraphHistory.read(month, in: context, otherIncome: otherIncome())
            .graph(side, of: month, recurring: recurring, today: today, comparingWith: choice)
    }

    /// The months Home's strip offers, from what it reads from the store (``MonthGraphHistory``). Saves first.
    func strip() throws -> [Period] {
        try context.save()
        return try MonthGraphHistory.read(CalendarMonth(today), in: context, otherIncome: otherIncome())
            .strip(.month, today: today)
    }
}
