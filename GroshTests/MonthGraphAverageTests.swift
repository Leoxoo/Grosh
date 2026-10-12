import SwiftData
import Testing
@testable import Grosh

/// The gray line of Home's Spent and Income cards: the Average of up to three complete months before the month shown,
/// each laid out across the month shown.
@MainActor
struct MonthGraphAverageTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// Where this month's gray line ends: the Average through the month's last day.
    private func averageAtMonthEnd(_ side: SpentOrIncome) throws -> Money? {
        try store.graph(side).comparisonLine?.last?.total
    }

    // MARK: Which months count

    /// A Starting balance and a transaction excluded from report count on neither card.
    @Test(arguments: SpentOrIncome.allCases)
    func withNothingThatCountsThereIsNoGrayLine(side: SpentOrIncome) throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2026, 7, 1), in: context)
        let excluded = try store.record(-40_00, "Café", on: day(2026, 8, 3))
        excluded.isExcludedFromReport = true

        let card = try store.graph(side)

        #expect(card.comparisonLine == nil)
        #expect(card.popup(on: today).comparison == nil)
    }

    @Test func theMonthShownIsNeverPartOfItsOwnAverage() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))

        #expect(try store.graph(.spent).comparisonLine == nil)
        #expect(try store.graph(.income).comparisonLine == nil)
    }

    /// September 15th ends halfway through September, so on October's chart it falls between the ends of the 15th and
    /// the 16th. The gray line runs on to the end of October, past today where the line stops.
    @Test func withOneCompleteMonthTheAverageIsThatMonthLaidOutAcrossThisOne() throws {
        try store.record(-30_00, "Café", on: day(2026, 9, 15))

        let spent = try store.graph(.spent)
        let average = try #require(spent.comparisonLine)

        #expect(spent.popup(on: day(2026, 10, 14)).comparison == Money(cents: 0))
        #expect(spent.popup(on: day(2026, 10, 15)).comparison == Money(cents: 15_48))
        #expect(spent.popup(on: day(2026, 10, 16)).comparison == Money(cents: 30_00))
        #expect(average.count == 32)
        #expect(average.last?.position == 1)
        #expect(average.last?.total == Money(cents: 30_00))
        #expect(spent.line.count == 13)
    }

    @Test func withTwoCompleteMonthsTheAverageIsTheirMean() throws {
        try store.record(-40_00, "Café", on: day(2026, 8, 1))
        try store.record(-20_00, "Café", on: day(2026, 9, 1))

        #expect(try averageAtMonthEnd(.spent) == Money(cents: 30_00))
    }

    /// June would be a fourth month.
    @Test func withMoreThanThreeCompleteMonthsOnlyTheThreeBeforeTheMonthShownCount() throws {
        try store.record(-500_00, "Rentals", on: day(2026, 6, 5))
        try store.record(-30_00, "Café", on: day(2026, 7, 2))
        try store.record(-60_00, "Café", on: day(2026, 8, 2))
        try store.record(-90_00, "Café", on: day(2026, 9, 2))

        #expect(try averageAtMonthEnd(.spent) == Money(cents: 60_00))
    }

    /// The first transaction that counts is on August 20th: August counts as a whole month, at zero until the 20th, and
    /// July doesn't count. On October 10th the mean takes in September 5th's $20 but not yet August 20th's $40.
    @Test func aPartialFirstMonthCountsAndTheMonthBeforeItDoesNot() throws {
        try store.record(-40_00, "Café", on: day(2026, 8, 20))
        try store.record(-20_00, "Café", on: day(2026, 9, 5))

        let spent = try store.graph(.spent)

        #expect(spent.popup(on: day(2026, 10, 10)).comparison == Money(cents: 10_00))
        #expect(spent.comparisonLine?.last?.total == Money(cents: 30_00))
    }

    /// Neither the Starting balance in July nor the excluded transaction in August counts, so the months start with
    /// September.
    @Test func aMonthBeforeTheFirstTransactionThatCountsIsLeftOut() throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2026, 7, 1), in: context)
        let excluded = try store.record(-40_00, "Café", on: day(2026, 8, 3))
        excluded.isExcludedFromReport = true
        try store.record(-30_00, "Café", on: day(2026, 9, 10))

        #expect(try averageAtMonthEnd(.spent) == Money(cents: 30_00))
    }

    @Test func aMonthWithNoEntriesCountsAsZero() throws {
        try store.record(-30_00, "Café", on: day(2026, 7, 3))
        try store.record(-60_00, "Café", on: day(2026, 9, 3))

        #expect(try averageAtMonthEnd(.spent) == Money(cents: 30_00))
    }

    /// July and September hold only spending, August only income, and every one of them counts on both cards.
    @Test func aMonthWithNothingForTheCardCountsAsZeroOnIt() throws {
        try store.record(-30_00, "Café", on: day(2026, 7, 3))
        try store.record(900_00, "Salary", .income, on: day(2026, 8, 3))
        try store.record(-60_00, "Café", on: day(2026, 9, 3))

        #expect(try averageAtMonthEnd(.spent) == Money(cents: 30_00))
        #expect(try averageAtMonthEnd(.income) == Money(cents: 300_00))
    }

    // MARK: Months of different lengths

    /// A dollar every day of the month before the one shown, which has 28 days for February 2026, 29 for February 2024,
    /// 30 for September and 31 for January. Laid out across the month shown, the gray line rises the whole way and ends
    /// at that month's full total.
    @Test(arguments: [
        CalendarMonth(year: 2026, month: 2), CalendarMonth(year: 2024, month: 2),
        CalendarMonth(year: 2026, month: 9), CalendarMonth(year: 2026, month: 1),
    ])
    func monthsOfEveryLengthLineUpWithNoDropAtTheEnd(earlier: CalendarMonth) throws {
        for number in 1...earlier.dayCount {
            try store.record(-1_00, "Café", on: earlier.day(number))
        }
        let shown = earlier.adding(months: 1)

        let average = try #require(try store.graph(.spent, in: shown).comparisonLine)

        #expect(average.count == shown.dayCount + 1)
        #expect(average.last?.position == 1)
        #expect(average.last?.total == Money(cents: earlier.dayCount * 1_00))
        #expect(zip(average, average.dropFirst()).allSatisfy { $0.total.cents < $1.total.cents })
    }

    // MARK: The popup

    @Test func thePopupShowsTheAverageOnTheSelectedDay() throws {
        try store.record(-60_00, "Rentals", on: day(2026, 9, 1))
        try store.record(-10_00, "Café", on: day(2026, 10, 3))

        let spent = try store.graph(.spent)
        let popup = spent.popup(on: today)

        #expect(popup.total == Money(cents: 10_00))
        #expect(popup.comparison == Money(cents: 60_00))
        #expect(spent.headline == Money(cents: 10_00))
    }

    /// Later days of this month have no running total yet.
    @Test func aDayWithNoDataThisMonthShowsOnlyTheDateAndTheAverage() throws {
        try store.record(-60_00, "Rentals", on: day(2026, 9, 1))
        try store.record(-10_00, "Café", on: day(2026, 10, 3))

        let popup = try store.graph(.spent).popup(on: day(2026, 10, 20))

        #expect(popup.day == day(2026, 10, 20))
        #expect(popup.total == nil)
        #expect(popup.comparison == Money(cents: 60_00))
    }
}
