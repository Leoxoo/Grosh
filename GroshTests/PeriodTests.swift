import Testing
@testable import Grosh

/// Which days each period of the Transactions tab covers, and the strip of periods it steps through.
struct PeriodTests {
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    @Test func aPastMonthRunsFromItsFirstDayToItsLastDay() {
        let august = Period.month(CalendarMonth(year: 2026, month: 8))

        #expect(august.days(today: today) == DayRange(first: day(2026, 8, 1), last: day(2026, 8, 31)))
    }

    @Test func thisMonthEndsTodayBecauseLaterDaysBelongToFuture() {
        let october = Period.month(CalendarMonth(year: 2026, month: 10))

        #expect(october.days(today: today) == DayRange(first: day(2026, 10, 1), last: today))
    }

    @Test(arguments: [(2026, 28), (2024, 29)])
    func februaryEndsOnItsLastDay(year: Int, lastDay: Int) {
        let february = Period.month(CalendarMonth(year: year, month: 2))

        #expect(february.days(today: today) == DayRange(first: day(year, 2, 1), last: day(year, 2, lastDay)))
    }

    @Test func futureStartsTomorrowAndHasNoEnd() {
        #expect(Period.future.days(today: today) == DayRange(first: day(2026, 10, 10), last: nil))
    }

    @Test func futureStartsInTheNextYearOnNewYearsEve() {
        #expect(Period.future.days(today: day(2026, 12, 31)).first == day(2027, 1, 1))
    }

    @Test func eachDayBelongsToExactlyOnePeriodOfTheStrip() {
        let strip = TimeRange.month.periods(from: day(2026, 8, 1), today: today)
        let days = [day(2026, 8, 1), day(2026, 8, 31), day(2026, 9, 1), today, day(2026, 10, 10), day(2027, 3, 1)]

        let holders = days.map { day in strip.filter { $0.days(today: today).contains(day) } }

        #expect(holders == [
            [.month(CalendarMonth(year: 2026, month: 8))],
            [.month(CalendarMonth(year: 2026, month: 8))],
            [.month(CalendarMonth(year: 2026, month: 9))],
            [.month(CalendarMonth(year: 2026, month: 10))],
            [.future],
            [.future],
        ])
    }

    // MARK: The strip

    @Test func theStripGoesFromTheFirstMonthWithDataThroughThisMonthThenFuture() {
        let strip = TimeRange.month.periods(from: day(2026, 8, 15), today: today)

        #expect(strip == [
            .month(CalendarMonth(year: 2026, month: 8)),
            .month(CalendarMonth(year: 2026, month: 9)),
            .month(CalendarMonth(year: 2026, month: 10)),
            .future,
        ])
    }

    @Test func theStripStepsAcrossTheYearEnd() {
        let strip = TimeRange.month.periods(from: day(2025, 11, 30), today: day(2026, 2, 3))

        #expect(strip == [
            .month(CalendarMonth(year: 2025, month: 11)),
            .month(CalendarMonth(year: 2025, month: 12)),
            .month(CalendarMonth(year: 2026, month: 1)),
            .month(CalendarMonth(year: 2026, month: 2)),
            .future,
        ])
    }

    @Test(arguments: [nil, CalendarDay(year: 2026, month: 12, day: 25)])
    func withNoDataBeforeTodayTheStripIsThisMonthAndFuture(earliest: CalendarDay?) {
        let strip = TimeRange.month.periods(from: earliest, today: today)

        #expect(strip == [.month(CalendarMonth(year: 2026, month: 10)), .future])
    }

    @Test func theStripReadsOlderMonthsThenLastMonthThisMonthAndFuture() {
        let strip = TimeRange.month.periods(from: day(2025, 12, 1), today: day(2026, 3, 9))

        #expect(strip.map { $0.title(today: day(2026, 3, 9)) } == ["12/2025", "01/2026", "Last month", "This month", "Future"])
    }
}
