import SwiftData
import Testing
@testable import Grosh

/// The Opening and Ending balances at the top of the Transactions tab, for every time range of the "…" menu.
@MainActor
struct TimeRangeBalanceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    /// A Friday.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let monday = 2
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = Wallet(name: "Checking")
        container.mainContext.insert(checking)
        record(1_000_00, on: day(2026, 7, 1))
        record(-100_00, on: day(2026, 9, 30))
        record(-50_00, on: day(2026, 10, 5))
        record(-20_00, on: today)
        record(-300_00, on: day(2026, 10, 10))
        record(5_00, on: day(2027, 1, 1))
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func record(_ cents: Int, on day: CalendarDay) {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = checking
    }

    private var transactions: [Transaction] { checking.transactions ?? [] }

    private func summary(of period: Period) -> PeriodSummary {
        PeriodSummary(of: transactions, in: period, today: today)
    }

    private func summaries(_ range: TimeRange) -> [PeriodSummary] {
        range.periods(from: day(2026, 7, 1), today: today, firstWeekday: monday).map(summary(of:))
    }

    @Test(arguments: [TimeRange.day, .week, .month, .quarter, .year, .all])
    func eachPeriodOfTheStripOpensWithTheEndingBalanceOfThePeriodBeforeIt(range: TimeRange) {
        let summaries = summaries(range)

        #expect(summaries.first?.openingBalance == Money(cents: 0))
        for (previous, next) in zip(summaries, summaries.dropFirst()) {
            #expect(next.openingBalance == previous.endingBalance)
        }
    }

    @Test(arguments: [TimeRange.day, .week, .month, .quarter, .year, .all])
    func thePeriodHoldingTodayEndsWithTheWalletsBalanceAndFutureWithTheProjectedOne(range: TimeRange) {
        let summaries = summaries(range)

        #expect(summaries.dropLast().last?.endingBalance == Money(cents: 830_00))
        #expect(summaries.last?.openingBalance == Money(cents: 830_00))
        #expect(summaries.last?.endingBalance == Money(cents: 535_00))
    }

    @Test(arguments: [
        (TimeRange.day, 850_00),
        (.week, 900_00),
        (.month, 900_00),
        (.quarter, 900_00),
        (.year, 0),
        (.all, 0),
    ])
    func thePeriodHoldingTodayOpensWithEverythingBeforeIt(range: TimeRange, openingCents: Int) {
        let current = summary(of: range.period(containing: today, firstWeekday: monday))

        #expect(current.openingBalance == Money(cents: openingCents))
        #expect(current.endingBalance == Money(cents: 830_00))
    }

    @Test func aCustomRangeOpensTheDayBeforeItsFirstDayAndEndsOnItsLastDayEvenPastToday() {
        let custom = TimeRange.custom(DayRange(first: day(2026, 9, 30), last: day(2026, 10, 10)))

        let summary = summary(of: custom.period(containing: today))

        #expect(summary.openingBalance == Money(cents: 1_000_00))
        #expect(summary.endingBalance == Money(cents: 530_00))
        #expect(summary.difference == Money(cents: -470_00))
    }
}
