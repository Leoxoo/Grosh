import Testing
@testable import Grosh

/// When a Recurring transaction falls due: the due days of each repeat, where its end cuts them off, and which one
/// comes next. The expected days are worked out by hand from the calendar, not by the code under test.
struct RepeatScheduleTests {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    @Test func dailyRepeatFallsOnEveryDay() {
        let schedule = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .day, every: 1), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2026, 10, 7)) == [
            day(2026, 10, 4), day(2026, 10, 5), day(2026, 10, 6), day(2026, 10, 7),
        ])
    }

    /// October 1, 2026 is a Thursday, so every week's occurrence stays on Thursday.
    @Test func weeklyRepeatKeepsTheStartWeekday() {
        let schedule = RepeatSchedule(start: day(2026, 10, 1), rule: RepeatRule(unit: .week, every: 1), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2026, 10, 31)) == [
            day(2026, 10, 1), day(2026, 10, 8), day(2026, 10, 15), day(2026, 10, 22), day(2026, 10, 29),
        ])
    }

    @Test func biWeeklyRepeatSkipsEveryOtherWeek() {
        let schedule = RepeatSchedule(start: day(2026, 10, 1), rule: RepeatRule(unit: .week, every: 2), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2026, 10, 31)) == [
            day(2026, 10, 1), day(2026, 10, 15), day(2026, 10, 29),
        ])
    }

    /// A monthly schedule from January 31 falls back to the last day of shorter months, then goes back to the 31st,
    /// because every month is counted from the start day.
    @Test func monthlyRepeatFallsBackToTheLastDayOfShorterMonths() {
        let schedule = RepeatSchedule(start: day(2026, 1, 31), rule: RepeatRule(unit: .month, every: 1), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2026, 5, 31)) == [
            day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30), day(2026, 5, 31),
        ])
    }

    @Test func monthlyRepeatUsesFebruary29InALeapYear() {
        let schedule = RepeatSchedule(start: day(2028, 1, 31), rule: RepeatRule(unit: .month, every: 1), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2028, 3, 31)) == [
            day(2028, 1, 31), day(2028, 2, 29), day(2028, 3, 31),
        ])
    }

    /// "Every 2 months on the 4th, until Dec 2027".
    @Test func everyTwoMonthsOnTheFourthUntilDecember2027() {
        let schedule = RepeatSchedule(
            start: day(2026, 10, 4), rule: RepeatRule(unit: .month, every: 2), end: .until(day(2027, 12, 31))
        )

        #expect(schedule.occurrences(after: nil, through: day(2030, 1, 1)) == [
            day(2026, 10, 4), day(2026, 12, 4), day(2027, 2, 4), day(2027, 4, 4),
            day(2027, 6, 4), day(2027, 8, 4), day(2027, 10, 4), day(2027, 12, 4),
        ])
    }

    @Test func yearlyRepeatFromLeapDayFallsBackInCommonYears() {
        let schedule = RepeatSchedule(start: day(2028, 2, 29), rule: RepeatRule(unit: .year, every: 1), end: .forever)

        #expect(schedule.occurrences(after: nil, through: day(2032, 2, 29)) == [
            day(2028, 2, 29), day(2029, 2, 28), day(2030, 2, 28), day(2031, 2, 28), day(2032, 2, 29),
        ])
    }

    @Test func untilDateIsIncluded() {
        let schedule = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .month, every: 1), end: .until(day(2026, 12, 4)))

        #expect(schedule.occurrences(after: nil, through: day(2027, 6, 1)) == [
            day(2026, 10, 4), day(2026, 11, 4), day(2026, 12, 4),
        ])
    }

    @Test func afterCountStopsAfterThatManyOccurrences() {
        let schedule = RepeatSchedule(start: day(2026, 10, 1), rule: RepeatRule(unit: .month, every: 1), end: .afterCount(3))

        #expect(schedule.occurrences(after: nil, through: day(2030, 1, 1)) == [
            day(2026, 10, 1), day(2026, 11, 1), day(2026, 12, 1),
        ])
        #expect(schedule.nextOccurrence(after: day(2026, 12, 1)) == nil)
    }

    @Test func occurrencesAfterAPreviousDayLeaveOutTheDaysUpToIt() {
        let schedule = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .day, every: 1), end: .forever)

        #expect(schedule.occurrences(after: day(2026, 10, 4), through: day(2026, 10, 6)) == [
            day(2026, 10, 5), day(2026, 10, 6),
        ])
    }

    @Test func nextOccurrenceIsTheStartDayUntilItPasses() {
        let schedule = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .month, every: 1), end: .forever)

        #expect(schedule.nextOccurrence(after: nil) == day(2026, 10, 4))
        #expect(schedule.nextOccurrence(after: day(2026, 10, 9)) == day(2026, 11, 4))
    }

    /// A rule of zero would never move on; it counts as one, so the walk always ends.
    @Test func aZeroIntervalCountsAsOne() {
        let schedule = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .day, every: 0), end: .forever)

        #expect(schedule.nextOccurrence(after: day(2026, 10, 6)) == day(2026, 10, 7))
    }

    /// A custom repeat counts in its own unit: every 3 days, or every 2 years.
    @Test func customRepeatsCountInTheirOwnUnit() {
        let everyThreeDays = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .day, every: 3), end: .forever)
        #expect(everyThreeDays.occurrences(after: nil, through: day(2026, 10, 10)) == [
            day(2026, 10, 4), day(2026, 10, 7), day(2026, 10, 10),
        ])

        let everyTwoYears = RepeatSchedule(start: day(2026, 10, 4), rule: RepeatRule(unit: .year, every: 2), end: .forever)
        #expect(everyTwoYears.occurrences(after: nil, through: day(2031, 1, 1)) == [
            day(2026, 10, 4), day(2028, 10, 4), day(2030, 10, 4),
        ])
    }

    /// The repeat as the form and the detail screen word it, in English: the day it falls on and when it ends.
    @Test func theSummaryNamesTheRepeatDayAndEnd() {
        let monthly = RepeatSchedule(
            start: day(2026, 10, 4), rule: RepeatRule(unit: .month, every: 2), end: .until(day(2027, 12, 4))
        )
        #expect(monthly.summary == "Every 2 months on the 4th, until Dec 2027")

        let once = RepeatSchedule(start: day(2026, 10, 1), rule: RepeatRule(unit: .week, every: 1), end: .afterCount(1))
        #expect(once.summary == "Every week, once")
    }
}
