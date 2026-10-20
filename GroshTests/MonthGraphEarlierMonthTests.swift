import SwiftData
import Testing
@testable import Grosh

/// The month strip above Home's Spent and Income cards, and an earlier month picked in it: complete, compared with the
/// three complete months before it, and selected on its last day to start with.
@MainActor
struct MonthGraphEarlierMonthTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    private func month(_ year: Int, _ month: Int) -> CalendarMonth {
        CalendarMonth(year: year, month: month)
    }

    // MARK: The month strip

    @Test func withNoTransactionsTheStripHoldsOnlyThisMonth() throws {
        #expect(try store.strip() == [.month(month(2026, 10))])
    }

    /// The Starting balance, the excluded transaction and the one in Recently Deleted count on neither card, so the
    /// strip starts in August; the transaction dated next month doesn't take it past this month, and it never holds
    /// Future.
    @Test func theStripRunsFromTheMonthOfTheFirstTransactionThatCountsThroughThisMonth() throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2026, 5, 1), in: context)
        let deleted = try store.record(-15_00, "Café", on: day(2026, 6, 4))
        try [deleted].delete(.onlySelected, in: context)
        let excluded = try store.record(-40_00, "Café", on: day(2026, 7, 3))
        excluded.isExcludedFromReport = true
        try store.record(1_500_00, "Salary", .income, on: day(2026, 8, 20))
        try store.record(-25_00, "Café", on: day(2026, 9, 5))
        try store.record(-100_00, "Rentals", on: day(2026, 11, 3))

        let strip = try store.strip()

        #expect(strip == [.month(month(2026, 8)), .month(month(2026, 9)), .month(month(2026, 10))])
        #expect(strip.map { $0.title(today: today) } == ["08/2026", "Last month", "This month"])
    }

    /// July's only transaction that counts is deleted, so the strip drops July: a card left on July shows this month,
    /// and one on September stays there.
    @Test func aMonthTheStripNoLongerOffersGivesWayToThisMonth() throws {
        let coffee = try store.record(-15_00, "Café", on: day(2026, 7, 4))
        try store.record(-25_00, "Café", on: day(2026, 9, 5))
        var july = Period.month(month(2026, 7))
        var september = Period.month(month(2026, 9))

        try [coffee].delete(.onlySelected, in: context)
        let strip = try store.strip()
        july.showCurrentPeriod(.month(month(2026, 10)), unlessOfferedBy: strip)
        september.showCurrentPeriod(.month(month(2026, 10)), unlessOfferedBy: strip)

        #expect(july == .month(month(2026, 10)))
        #expect(september == .month(month(2026, 9)))
    }

    // MARK: An earlier month

    /// March would be a fourth month before July, and August, September and October come after it: only April, May and
    /// June make July's Average. July's line runs to the end of its last day.
    @Test func anEarlierMonthShowsItsFullTotalBesideTheAverageOfTheThreeCompleteMonthsBeforeIt() throws {
        try store.record(-900_00, "Rentals", on: day(2026, 3, 2))
        try store.record(-30_00, "Café", on: day(2026, 4, 2))
        try store.record(-60_00, "Café", on: day(2026, 5, 2))
        try store.record(-90_00, "Café", on: day(2026, 6, 2))
        try store.record(-10_00, "Café", on: day(2026, 7, 1))
        try store.record(-20_00, "Café", on: day(2026, 7, 31))
        try store.record(-500_00, "Rentals", on: day(2026, 8, 2))
        try store.record(-700_00, "Rentals", on: day(2026, 9, 2))
        try store.record(-1_000_00, "Rentals", on: day(2026, 10, 2))

        let july = try store.graph(.spent, in: month(2026, 7))

        #expect(july.headline == Money(cents: 30_00))
        #expect(july.line.count == 32)
        #expect(july.line.last?.position == 1)
        #expect(july.popup(on: day(2026, 7, 30)).total == Money(cents: 10_00))
        #expect(july.popup(on: day(2026, 7, 31)).total == Money(cents: 30_00))
        #expect(july.comparisonLine?.last?.position == 1)
        #expect(july.comparisonLine?.last?.total == Money(cents: 60_00))
    }

    /// June, July and August average $60; September's own $40 is its total.
    @Test func anEarlierMonthStartsOnItsLastDaySoItsFinalTotalAndAverageShow() throws {
        try store.record(-30_00, "Café", on: day(2026, 6, 10))
        try store.record(-60_00, "Café", on: day(2026, 7, 10))
        try store.record(-90_00, "Café", on: day(2026, 8, 10))
        try store.record(-40_00, "Café", on: day(2026, 9, 15))

        let september = try store.graph(.spent, in: month(2026, 9))
        let popup = september.popup(on: september.defaultSelection)

        #expect(september.defaultSelection == day(2026, 9, 30))
        #expect(popup.total == Money(cents: 40_00))
        #expect(popup.comparison == Money(cents: 60_00))
    }

    // MARK: The legend

    @Test func theLegendNamesTheLineAsTheStripNamesTheMonth() throws {
        #expect(try store.graph(.spent, in: month(2026, 10)).lineName == "This month")
        #expect(try store.graph(.income, in: month(2026, 9)).lineName == "Last month")
        #expect(try store.graph(.spent, in: month(2026, 7)).lineName == "07/2026")
    }
}
