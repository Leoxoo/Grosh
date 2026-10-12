import SwiftData
import Testing
@testable import Grosh

/// The month strip above Home's Spent and Income cards, and an earlier month picked in it: complete, compared with the
/// three complete months before it, and selected on its last day to start with.
@MainActor
struct MonthGraphEarlierMonthTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The 12th of a 31-day month, after a 30-day September.
    private let today = day(2026, 10, 12)

    init() throws {
        store = try CategoryFixture()
    }

    /// Records `cents` (signed, as it moves the wallet) filed under `categoryName` on `day`, in Checking.
    @discardableResult
    private func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay
    ) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = store.wallet
        transaction.category = try store.category(categoryName, type)
        return transaction
    }

    /// Every transaction in the store, those in Recently Deleted included.
    private func transactions() throws -> [Transaction] {
        try context.fetch(FetchDescriptor<Transaction>())
    }

    /// The card for `side` showing `month`.
    private func graph(_ side: SpentOrIncome, in month: CalendarMonth) throws -> MonthGraph {
        try MonthGraph(side, of: transactions(), in: month, today: today)
    }

    private func month(_ year: Int, _ month: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month)
    }

    // MARK: The month strip

    @Test func withNoTransactionsTheStripHoldsOnlyThisMonth() throws {
        #expect(try MonthGraph.months(of: transactions(), today: today) == [.month(month(2026, 10))])
    }

    /// The Starting balance, the excluded transaction and the one in Recently Deleted count on neither card, so the
    /// strip starts in August; the transaction dated next month doesn't take it past this month, and it never holds
    /// Future.
    @Test func theStripRunsFromTheMonthOfTheFirstTransactionThatCountsThroughThisMonth() throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2026, 5, 1), in: context)
        let deleted = try record(-15_00, "Café", on: day(2026, 6, 4))
        try [deleted].delete(.onlySelected, in: context)
        let excluded = try record(-40_00, "Café", on: day(2026, 7, 3))
        excluded.isExcludedFromReport = true
        try record(1_500_00, "Salary", .income, on: day(2026, 8, 20))
        try record(-25_00, "Café", on: day(2026, 9, 5))
        try record(-100_00, "Rentals", on: day(2026, 11, 3))

        let strip = try MonthGraph.months(of: transactions(), today: today)

        #expect(strip == [.month(month(2026, 8)), .month(month(2026, 9)), .month(month(2026, 10))])
        #expect(strip.map { $0.title(today: today) } == ["08/2026", "Last month", "This month"])
    }

    // MARK: An earlier month

    /// March would be a fourth month before July, and August, September and October come after it: only April, May and
    /// June make July's Average. July's line runs to the end of its last day.
    @Test func anEarlierMonthShowsItsFullTotalBesideTheAverageOfTheThreeCompleteMonthsBeforeIt() throws {
        try record(-900_00, "Rentals", on: day(2026, 3, 2))
        try record(-30_00, "Café", on: day(2026, 4, 2))
        try record(-60_00, "Café", on: day(2026, 5, 2))
        try record(-90_00, "Café", on: day(2026, 6, 2))
        try record(-10_00, "Café", on: day(2026, 7, 1))
        try record(-20_00, "Café", on: day(2026, 7, 31))
        try record(-500_00, "Rentals", on: day(2026, 8, 2))
        try record(-700_00, "Rentals", on: day(2026, 9, 2))
        try record(-1_000_00, "Rentals", on: day(2026, 10, 2))

        let july = try graph(.spent, in: month(2026, 7))

        #expect(july.headline == Money(cents: 30_00))
        #expect(july.line.count == 32)
        #expect(july.line.last?.position == 1)
        #expect(july.popup(on: day(2026, 7, 30)).total == Money(cents: 10_00))
        #expect(july.popup(on: day(2026, 7, 31)).total == Money(cents: 30_00))
        #expect(july.averageLine?.last?.position == 1)
        #expect(july.averageLine?.last?.total == Money(cents: 60_00))
    }

    /// June, July and August average $60; September's own $40 is its total.
    @Test func anEarlierMonthStartsOnItsLastDaySoItsFinalTotalAndAverageShow() throws {
        try record(-30_00, "Café", on: day(2026, 6, 10))
        try record(-60_00, "Café", on: day(2026, 7, 10))
        try record(-90_00, "Café", on: day(2026, 8, 10))
        try record(-40_00, "Café", on: day(2026, 9, 15))

        let september = try graph(.spent, in: month(2026, 9))
        let popup = september.popup(on: september.defaultSelection)

        #expect(september.defaultSelection == day(2026, 9, 30))
        #expect(popup.total == Money(cents: 40_00))
        #expect(popup.average == Money(cents: 60_00))
    }

    // MARK: The legend

    @Test func theLegendNamesTheLineAsTheStripNamesTheMonth() throws {
        #expect(try graph(.spent, in: month(2026, 10)).lineName == "This month")
        #expect(try graph(.income, in: month(2026, 9)).lineName == "Last month")
        #expect(try graph(.spent, in: month(2026, 7)).lineName == "07/2026")
    }
}
