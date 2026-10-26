import Testing
@testable import Grosh

/// Income and Spent details' Daily average: a period's total divided by the days it covers, through today in the current
/// period and every day of a past one.
@Suite(.namedInTheLog)
struct DailyAverageTests {
    /// The ticket's example: $3,492.87 over Oct 1–16 is $218.30 a day.
    @Test func dividesTheTotalByTheDaysThroughToday() {
        let days = DayRange(first: day(2026, 10, 1), last: day(2026, 10, 16))
        #expect(DailyAverage.of(Money(cents: 3_492_87), over: days) == Money(cents: 218_30))
    }

    @Test func aPastMonthDividesByEveryDayOfIt() {
        let september = DayRange(first: day(2026, 9, 1), last: day(2026, 9, 30))
        #expect(DailyAverage.of(Money(cents: 300_00), over: september) == Money(cents: 10_00))
    }

    @Test func roundsToTheCent() {
        let days = DayRange(first: day(2026, 10, 1), last: day(2026, 10, 3))
        #expect(DailyAverage.of(Money(cents: 100_00), over: days) == Money(cents: 33_33))
        #expect(DailyAverage.of(Money(cents: 200_00), over: days) == Money(cents: 66_67))
    }

    /// A span with no start, as All time's before its first transaction, has no days to divide by.
    @Test func noAverageWithoutAStartDay() {
        #expect(DailyAverage.of(Money(cents: 100_00), over: DayRange(first: nil, last: day(2026, 10, 16))) == nil)
    }
}
