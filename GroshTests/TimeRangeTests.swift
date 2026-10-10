import Testing
@testable import Grosh

/// The time ranges of the Transactions tab's "…" menu: which periods the strip steps through for each, which days
/// each period covers, and what the strip calls them.
struct TimeRangeTests {
    /// A Friday.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let monday = 2

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    // MARK: Day

    @Test func theDayStripGoesFromTheFirstDayWithDataThroughTodayThenFuture() {
        let strip = TimeRange.day.periods(from: day(2026, 10, 6), today: today, firstWeekday: monday)

        #expect(strip == [
            .day(day(2026, 10, 6)), .day(day(2026, 10, 7)), .day(day(2026, 10, 8)), .day(today), .future,
        ])
    }

    @Test func theDayStripReadsOlderDaysThenYesterdayTodayAndFuture() {
        let strip = TimeRange.day.periods(from: day(2026, 10, 6), today: today, firstWeekday: monday)

        #expect(strip.map { $0.title(today: today) } == ["06/10/2026", "07/10/2026", "Yesterday", "Today", "Future"])
    }

    // MARK: Week

    @Test func theWeekStripStepsThroughWholeWeeksStartingOnTheFirstWeekday() {
        let strip = TimeRange.week.periods(from: day(2026, 9, 23), today: today, firstWeekday: monday)

        #expect(strip.map { $0.days(today: today) } == [
            DayRange(first: day(2026, 9, 21), last: day(2026, 9, 27)),
            DayRange(first: day(2026, 9, 28), last: day(2026, 10, 4)),
            DayRange(first: day(2026, 10, 5), last: today),
            DayRange(first: day(2026, 10, 10), last: nil),
        ])
    }

    @Test func whereWeeksStartOnSundayThisWeekStartsOnSunday() {
        let sunday = 1

        let thisWeek = TimeRange.week.period(containing: today, firstWeekday: sunday)

        #expect(thisWeek.days(today: today) == DayRange(first: day(2026, 10, 4), last: today))
    }

    @Test func theWeekStripReadsOlderWeeksThenLastWeekThisWeekAndFuture() {
        let strip = TimeRange.week.periods(from: day(2026, 9, 23), today: today, firstWeekday: monday)

        #expect(strip.map { $0.title(today: today) } == ["21/09 – 27/09/2026", "Last week", "This week", "Future"])
    }

    @Test func aWeekAcrossTheYearEndNamesBothYears() {
        let week = TimeRange.week.period(containing: day(2025, 12, 31), firstWeekday: monday)

        #expect(week.title(today: today) == "29/12/2025 – 04/01/2026")
    }

    // MARK: Quarter

    @Test func theQuarterStripStepsThroughCalendarQuarters() {
        let strip = TimeRange.quarter.periods(from: day(2025, 12, 14), today: today, firstWeekday: monday)

        #expect(strip.map { $0.days(today: today) } == [
            DayRange(first: day(2025, 10, 1), last: day(2025, 12, 31)),
            DayRange(first: day(2026, 1, 1), last: day(2026, 3, 31)),
            DayRange(first: day(2026, 4, 1), last: day(2026, 6, 30)),
            DayRange(first: day(2026, 7, 1), last: day(2026, 9, 30)),
            DayRange(first: day(2026, 10, 1), last: today),
            DayRange(first: day(2026, 10, 10), last: nil),
        ])
    }

    @Test func theQuarterStripReadsOlderQuartersThenLastQuarterThisQuarterAndFuture() {
        let strip = TimeRange.quarter.periods(from: day(2025, 12, 14), today: today, firstWeekday: monday)

        #expect(strip.map { $0.title(today: today) } == [
            "Q4 2025", "Q1 2026", "Q2 2026", "Last quarter", "This quarter", "Future",
        ])
    }

    // MARK: Year

    @Test func theYearStripStepsThroughCalendarYearsAndThisYearEndsToday() {
        let strip = TimeRange.year.periods(from: day(2023, 7, 4), today: today, firstWeekday: monday)

        #expect(strip.map { $0.days(today: today) } == [
            DayRange(first: day(2023, 1, 1), last: day(2023, 12, 31)),
            DayRange(first: day(2024, 1, 1), last: day(2024, 12, 31)),
            DayRange(first: day(2025, 1, 1), last: day(2025, 12, 31)),
            DayRange(first: day(2026, 1, 1), last: today),
            DayRange(first: day(2026, 10, 10), last: nil),
        ])
        #expect(strip.map { $0.title(today: today) } == ["2023", "2024", "Last year", "This year", "Future"])
    }

    // MARK: All

    @Test func allIsEverythingThroughTodayThenFuture() {
        let strip = TimeRange.all.periods(from: day(2020, 7, 1), today: today, firstWeekday: monday)

        #expect(strip.map { $0.days(today: today) } == [
            DayRange(first: nil, last: today),
            DayRange(first: day(2026, 10, 10), last: nil),
        ])
        #expect(strip.map { $0.title(today: today) } == ["All time", "Future"])
    }

    // MARK: Custom

    @Test func aCustomRangeIsOnePeriodCoveringExactlyTheChosenDaysEvenPastToday() {
        let chosen = TimeRange.custom(day(2026, 9, 15)...day(2026, 10, 31))

        let strip = chosen.periods(from: day(2020, 7, 1), today: today, firstWeekday: monday)

        #expect(strip.map { $0.days(today: today) } == [DayRange(first: day(2026, 9, 15), last: day(2026, 10, 31))])
        #expect(strip.map { $0.title(today: today) } == ["15/09/2026 – 31/10/2026"])
    }

    // MARK: Projected balance

    @Test func onlyAPeriodReachingPastTodayEndsWithAProjectedBalance() {
        #expect(Period.future.isProjected(today: today))
        #expect(Period.custom(day(2026, 10, 1)...day(2026, 10, 10)).isProjected(today: today))
        #expect(!Period.custom(day(2026, 10, 1)...today).isProjected(today: today))
        #expect(!Period.all.isProjected(today: today))
        #expect(!TimeRange.year.period(containing: today).isProjected(today: today))
    }
}
