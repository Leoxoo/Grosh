import Testing
@testable import Grosh

/// When a Recurring transaction falls due: the due days of each repeat, where its end cuts them off, and which one
/// comes next. The expected days are worked out by hand from the calendar, not by the code under test.
struct RepeatScheduleTests {
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

    /// A monthly repeat on the last day counts its start day as the first occurrence, then falls on each month's last
    /// day: from January 28, February 28, then March 31.
    @Test func lastDayRepeatFallsOnEachMonthsLastDay() {
        let schedule = RepeatSchedule(
            start: day(2026, 1, 28), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .lastDay
        )

        #expect(schedule.occurrences(after: nil, through: day(2026, 3, 31)) == [
            day(2026, 1, 28), day(2026, 2, 28), day(2026, 3, 31),
        ])
    }

    @Test func lastDayRepeatUsesFebruary29InALeapYear() {
        let schedule = RepeatSchedule(
            start: day(2028, 1, 28), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .lastDay
        )

        #expect(schedule.occurrences(after: nil, through: day(2028, 3, 31)) == [
            day(2028, 1, 28), day(2028, 2, 29), day(2028, 3, 31),
        ])
    }

    /// A start on the 31st is itself a last day, and February 2029 ends on the 28th.
    @Test func lastDayRepeatFromTheThirtyFirstFallsOnEachMonthsLastDay() {
        let schedule = RepeatSchedule(
            start: day(2028, 12, 31), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .lastDay
        )

        #expect(schedule.occurrences(after: nil, through: day(2029, 3, 31)) == [
            day(2028, 12, 31), day(2029, 1, 31), day(2029, 2, 28), day(2029, 3, 31),
        ])
    }

    /// October 29, 2026 is the fifth Thursday, so each month's occurrence is its last Thursday. October and December
    /// have five Thursdays; the other months have four, and their last one is the one that falls.
    @Test func fifthWeekdayRepeatFallsOnTheLastWeekdayOfEachMonth() {
        let schedule = RepeatSchedule(
            start: day(2026, 10, 29), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .nthWeekday
        )

        #expect(schedule.occurrences(after: nil, through: day(2027, 3, 31)) == [
            day(2026, 10, 29), day(2026, 11, 26), day(2026, 12, 31),
            day(2027, 1, 28), day(2027, 2, 25), day(2027, 3, 25),
        ])
    }

    /// October 13, 2026 is the second Tuesday, so each month's occurrence is that month's second Tuesday.
    @Test func nthWeekdayRepeatFallsOnTheSameWeekOfEachMonth() {
        let schedule = RepeatSchedule(
            start: day(2026, 10, 13), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .nthWeekday
        )

        #expect(schedule.occurrences(after: nil, through: day(2027, 3, 31)) == [
            day(2026, 10, 13), day(2026, 11, 10), day(2026, 12, 8),
            day(2027, 1, 12), day(2027, 2, 9), day(2027, 3, 9),
        ])
    }

    /// February 29, 2028 is a fifth Tuesday, so it stands for the last Tuesday of February: the 29th in leap 2028 and
    /// the 27th in 2029, a common year.
    @Test func fifthWeekdayRepeatFallsOnTheLastWeekdayOfFebruary() {
        let schedule = RepeatSchedule(
            start: day(2028, 2, 29), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .nthWeekday
        )

        #expect(schedule.occurrences(after: nil, through: day(2028, 3, 31)) == [day(2028, 2, 29), day(2028, 3, 28)])
        #expect(schedule.occurrences(after: day(2028, 12, 31), through: day(2029, 2, 28)) == [
            day(2029, 1, 30), day(2029, 2, 27),
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

    /// The last day is offered only from the 28th on. The same day and the weekday are offered for every start.
    @Test func theLastDayIsOfferedOnlyFromTheTwentyEighth() {
        #expect(MonthlyDay.offered(startingOn: day(2026, 10, 27)) == [.sameDay, .nthWeekday])
        #expect(MonthlyDay.offered(startingOn: day(2026, 10, 28)) == [.sameDay, .nthWeekday, .lastDay])
        #expect(MonthlyDay.offered(startingOn: day(2026, 10, 31)) == [.sameDay, .nthWeekday, .lastDay])
    }

    /// Each monthly day is named in full, after "Every month", so the detail screen reads the chosen rule in full.
    @Test func theSummaryNamesTheMonthlyDayInFull() {
        let sameDay = RepeatSchedule(start: day(2026, 10, 29), rule: RepeatRule(unit: .month, every: 1), end: .forever)
        #expect(sameDay.summary == "Every month on the 29th")

        let fifthThursday = RepeatSchedule(
            start: day(2026, 10, 29), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .nthWeekday
        )
        #expect(fifthThursday.summary == "Every month on the last Thursday")

        let secondTuesday = RepeatSchedule(
            start: day(2026, 10, 13), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .nthWeekday
        )
        #expect(secondTuesday.summary == "Every month on the second Tuesday")

        let lastDay = RepeatSchedule(
            start: day(2026, 10, 31), rule: RepeatRule(unit: .month, every: 1), end: .forever, monthlyDay: .lastDay
        )
        #expect(lastDay.summary == "Every month on the last day")

        let everyTwoMonths = RepeatSchedule(
            start: day(2026, 10, 13), rule: RepeatRule(unit: .month, every: 2), end: .until(day(2027, 12, 4)),
            monthlyDay: .nthWeekday
        )
        #expect(everyTwoMonths.summary == "Every 2 months on the second Tuesday, until Dec 2027")
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
