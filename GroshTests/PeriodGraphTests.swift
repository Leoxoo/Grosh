import SwiftData
import Testing
@testable import Grosh

/// The Month graph generalized to a week, month, quarter or year, as the Income and Spent details' comparison card draws
/// it: the Average of up to three complete earlier periods of the same length, and the Wallet selector's choice.
@MainActor
@Suite(.namedInTheLog)
struct PeriodGraphTests {
    private let store: MonthGraphFixture
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// The graph of `side` for `period` as of today, Oct 12 2026, compared with the Average, for `selection`.
    private func graph(
        _ side: SpentOrIncome = .spent, _ period: Period, selection: WalletSelection = .total
    ) throws -> MonthGraph {
        let otherIncome = try store.otherIncome()
        let counted = try store.transactions().compactMap { $0.countedAmount(in: selection, otherIncome: otherIncome) }
        return MonthGraph(
            side, of: counted, countingFrom: counted.firstDay, recurring: [], in: period, today: today,
            comparingWith: .average, selection: selection
        )
    }

    /// A week's Average is the mean of the three earlier weeks: 140, nothing, and 70, so 70.
    @Test func aWeeksAverageIsTheMeanOfTheThreeEarlierWeeks() throws {
        try store.record(-70_00, "Café", on: day(2026, 9, 9))
        try store.record(-140_00, "Café", on: day(2026, 9, 22))
        try store.record(-35_00, "Café", on: day(2026, 9, 30))

        let week = try graph(.spent, .week(startingOn: day(2026, 9, 28)))
        #expect(week.headline == Money(cents: 35_00))
        #expect(week.comparisonLine?.last?.total == Money(cents: 70_00))
    }

    /// The week holding the first transaction that counts is the earliest one the Average takes, so a week before it is
    /// left out rather than counted as nothing: the Average is 120 and 60, so 90.
    @Test func earlierWeeksBeforeTheFirstCountedTransactionAreLeftOut() throws {
        try store.record(-60_00, "Café", on: day(2026, 9, 15))
        try store.record(-120_00, "Café", on: day(2026, 9, 22))
        try store.record(-35_00, "Café", on: day(2026, 9, 30))

        let week = try graph(.spent, .week(startingOn: day(2026, 9, 28)))
        #expect(week.comparisonLine?.last?.total == Money(cents: 90_00))
    }

    /// A week that starts on a Sunday takes the Sunday weeks before it, so the 35 in the week shown is not one of them:
    /// 140 and 60 make 100, whichever day the calendar's weeks start on.
    @Test func aWeekStartingOnASundayAveragesTheSundayWeeksBeforeIt() throws {
        try store.record(-60_00, "Café", on: day(2026, 9, 15))
        try store.record(-140_00, "Café", on: day(2026, 9, 22))
        try store.record(-35_00, "Café", on: day(2026, 9, 27))

        let week = try graph(.spent, .week(startingOn: day(2026, 9, 27)))
        #expect(week.headline == Money(cents: 35_00))
        #expect(week.comparisonLine?.last?.total == Money(cents: 100_00))
    }

    /// A quarter's earlier quarters are each stretched to its length: 300, nothing and 50, a mean of 116.67 at its end.
    @Test func aQuarterAveragesTheEarlierQuartersStretchedToItsLength() throws {
        try store.record(-50_00, "Café", on: day(2025, 10, 15))
        try store.record(-300_00, "Café", on: day(2026, 4, 10))

        let quarter = try graph(.spent, .quarter(year: 2026, quarter: 3))
        #expect(quarter.comparisonLine?.last?.total == Money(cents: 116_67))
    }

    @Test func aGraphCountsOnlyTheWalletItIsGiven() throws {
        let savings = Wallet(name: "Savings")
        store.context.insert(savings)
        try store.record(-25_00, "Café", on: day(2026, 10, 4), in: savings)
        try store.record(-40_00, "Café", on: day(2026, 10, 3))

        let october = Period.month(CalendarMonth(today))
        #expect(try graph(.spent, october, selection: .wallet(store.checking)).headline == Money(cents: 40_00))
        #expect(try graph(.spent, october, selection: .wallet(savings)).headline == Money(cents: 25_00))
        #expect(try graph(.spent, october).headline == Money(cents: 65_00))
    }

    /// Only the current period draws the dotted line; a past one has none.
    @Test func aPastPeriodHasNoDottedLine() throws {
        try store.record(-35_00, "Café", on: day(2026, 9, 30))
        #expect(try graph(.spent, .week(startingOn: day(2026, 9, 28))).scheduledLine == nil)
    }

    /// Last year is offered only for a month, as on Home's graph.
    @Test func onlyAMonthOffersLastYear() throws {
        #expect(try graph(.spent, .month(CalendarMonth(today))).offersLastYear)
        #expect(try !graph(.spent, .week(startingOn: day(2026, 10, 12))).offersLastYear)
        #expect(try !graph(.spent, .quarter(year: 2026, quarter: 3)).offersLastYear)
    }
}
