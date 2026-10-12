import SwiftData
import Testing
@testable import Grosh

/// The "vs last year" switch of Home's Spent and Income cards: with it on, the gray line is the same month 12 months
/// before the month shown when that card has something counted in it, and the Average when it doesn't.
@MainActor
struct MonthGraphLastYearTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    // MARK: The gray line

    /// October 2025 has 31 days like this October, so each of its days lines up with the same day this year. The gray
    /// line runs on to the end of the month, past today where the line stops.
    @Test func withTheSwitchOnTheGrayLineIsTheSameMonthLastYear() throws {
        try store.record(-40_00, "Café", on: day(2025, 10, 5))
        try store.record(-20_00, "Café", on: day(2025, 10, 20))
        try store.record(-300_00, "Rentals", on: day(2026, 9, 1))

        let spent = try store.graph(.spent, comparingWith: .lastYear)
        let lastYear = try #require(spent.comparisonLine)

        #expect(spent.isLastYearAvailable)
        #expect(spent.comparison == .lastYear)
        #expect(spent.comparison.name == "Last year")
        #expect(spent.popup(on: day(2026, 10, 4)).comparison == Money(cents: 0))
        #expect(spent.popup(on: day(2026, 10, 5)).comparison == Money(cents: 40_00))
        #expect(spent.popup(on: today).comparison == Money(cents: 40_00))
        #expect(lastYear.count == 32)
        #expect(lastYear.last?.position == 1)
        #expect(lastYear.last?.total == Money(cents: 60_00))
    }

    /// The same months as with the switch on: September's $300 over July, August and September makes an Average of
    /// $100.
    @Test func withTheSwitchOffTheGrayLineIsTheAverageThoughLastYearIsAvailable() throws {
        try store.record(-40_00, "Café", on: day(2025, 10, 5))
        try store.record(-20_00, "Café", on: day(2025, 10, 20))
        try store.record(-300_00, "Rentals", on: day(2026, 9, 1))

        let spent = try store.graph(.spent, comparingWith: .average)

        #expect(spent.isLastYearAvailable)
        #expect(spent.comparison == .average)
        #expect(spent.comparison.name == "Average")
        #expect(spent.comparisonLine?.last?.total == Money(cents: 100_00))
    }

    // MARK: When Last year is available

    /// October 2025 holds only a salary. Income compares with it; Spent's switch is greyed out and its card shows the
    /// Average, September's $60 over July, August and September.
    @Test func lastYearIsAvailableOnlyToTheCardWithSomethingCountedThatMonth() throws {
        try store.record(1_500_00, "Salary", .income, on: day(2025, 10, 25))
        try store.record(-60_00, "Café", on: day(2026, 9, 3))

        let spent = try store.graph(.spent, comparingWith: .lastYear)
        let income = try store.graph(.income, comparingWith: .lastYear)

        #expect(!spent.isLastYearAvailable)
        #expect(spent.comparison == .average)
        #expect(spent.comparisonLine?.last?.total == Money(cents: 20_00))
        #expect(income.isLastYearAvailable)
        #expect(income.comparison == .lastYear)
        #expect(income.comparisonLine?.last?.total == Money(cents: 1_500_00))
    }

    /// The Starting balance and the transaction excluded from report in October 2025 count on neither card, so the
    /// first month that counts is September 2026, and October 2025 comes before it.
    @Test(arguments: SpentOrIncome.allCases)
    func lastYearBeforeTheFirstTransactionThatCountsIsNotAvailable(side: SpentOrIncome) throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2025, 10, 1), in: context)
        let excluded = try store.record(-40_00, "Café", on: day(2025, 10, 3))
        excluded.isExcludedFromReport = true
        try store.record(-30_00, "Café", on: day(2026, 9, 10))
        try store.record(900_00, "Salary", .income, on: day(2026, 9, 25))

        let card = try store.graph(side, comparingWith: .lastYear)

        #expect(!card.isLastYearAvailable)
        #expect(card.comparison == .average)
        #expect(card.comparisonLine != nil)
    }

    // MARK: A leap-year February

    /// February 2024's 29th belongs to the February a year before February 2025, which has no 29th. Laid out across
    /// February 2025's 28 days, it ends the gray line at the end of the 28th, with no drop.
    @Test func theLeapDayIsLastYearForTheFebruaryAfterIt() throws {
        try store.record(-28_00, "Café", on: day(2024, 2, 29))

        let february = try store.graph(.spent, in: CalendarMonth(year: 2025, month: 2), comparingWith: .lastYear)
        let lastYear = try #require(february.comparisonLine)

        #expect(february.isLastYearAvailable)
        #expect(february.comparison == .lastYear)
        #expect(february.popup(on: day(2025, 2, 27)).comparison == Money(cents: 0))
        #expect(february.popup(on: day(2025, 2, 28)).comparison == Money(cents: 28_00))
        #expect(lastYear.count == 29)
        #expect(lastYear.last?.position == 1)
    }

    /// February 2023 has no 29th to be a year before February 29th, 2024, and nothing on its own days: the 1st of March
    /// isn't February. The card shows the Average, December's $60 over November, December and January.
    @Test func aLeapYearFebruaryWithNothingTheFebruaryBeforeShowsTheAverage() throws {
        try store.record(-30_00, "Café", on: day(2023, 1, 31))
        try store.record(-30_00, "Café", on: day(2023, 3, 1))
        try store.record(-60_00, "Café", on: day(2023, 12, 10))

        let february = try store.graph(.spent, in: CalendarMonth(year: 2024, month: 2), comparingWith: .lastYear)
        let average = try #require(february.comparisonLine)

        #expect(!february.isLastYearAvailable)
        #expect(february.comparison == .average)
        #expect(average.count == 30)
        #expect(average.last?.total == Money(cents: 20_00))
    }

    // MARK: A switch left on

    /// October 2025 holds nothing, so this October shows the Average, August's $90 over July, August and September.
    /// September has September 2025's $50 a year before it, so the switch still on shows Last year there again.
    @Test func aSwitchLeftOnShowsLastYearAgainOnAMonthThatHasIt() throws {
        try store.record(-50_00, "Café", on: day(2025, 9, 10))
        try store.record(-90_00, "Café", on: day(2026, 8, 5))

        let october = try store.graph(.spent, comparingWith: .lastYear)
        let september = try store.graph(.spent, in: CalendarMonth(year: 2026, month: 9), comparingWith: .lastYear)

        #expect(!october.isLastYearAvailable)
        #expect(october.comparison == .average)
        #expect(october.comparisonLine?.last?.total == Money(cents: 30_00))
        #expect(september.isLastYearAvailable)
        #expect(september.comparison == .lastYear)
        #expect(september.comparisonLine?.last?.total == Money(cents: 50_00))
    }
}
