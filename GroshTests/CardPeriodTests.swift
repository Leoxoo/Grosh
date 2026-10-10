import Foundation
import Testing
@testable import Grosh

/// Which days a Card's periods cover: a statement period runs from the day after one statement date through the next,
/// and a statement date of 29–31 falls on the month's last day in shorter months. Other Cards use calendar months.
struct CardPeriodTests {
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let unitedStates = Locale(identifier: "en_US")

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func statement(on statementDay: Int, holding day: CalendarDay) -> DayRange {
        CardPeriod(containing: day, statementDay: statementDay).days
    }

    // MARK: Statement periods

    @Test func theCurrentStatementRunsFromTheDayAfterThePreviousStatementDateThroughTheNext() {
        #expect(statement(on: 15, holding: today) == DayRange(first: day(2026, 9, 16), last: day(2026, 10, 15)))
    }

    @Test func theStatementDateIsTheLastDayOfItsPeriodAndTheNextDayStartsAnother() {
        #expect(statement(on: 15, holding: day(2026, 10, 15)) == DayRange(first: day(2026, 9, 16), last: day(2026, 10, 15)))
        #expect(statement(on: 15, holding: day(2026, 10, 16)) == DayRange(first: day(2026, 10, 16), last: day(2026, 11, 15)))
    }

    @Test func aStatementOnTheFirstRunsFromTheSecondThroughTheFirst() {
        #expect(statement(on: 1, holding: day(2026, 10, 1)) == DayRange(first: day(2026, 9, 2), last: day(2026, 10, 1)))
        #expect(statement(on: 1, holding: day(2026, 10, 2)) == DayRange(first: day(2026, 10, 2), last: day(2026, 11, 1)))
    }

    @Test func aStatementOnThe31stClosesOnTheLastDayOfEveryMonth() {
        #expect(statement(on: 31, holding: day(2026, 1, 31)) == DayRange(first: day(2026, 1, 1), last: day(2026, 1, 31)))
        #expect(statement(on: 31, holding: day(2026, 2, 10)) == DayRange(first: day(2026, 2, 1), last: day(2026, 2, 28)))
        #expect(statement(on: 31, holding: day(2026, 3, 1)) == DayRange(first: day(2026, 3, 1), last: day(2026, 3, 31)))
        #expect(statement(on: 31, holding: day(2026, 4, 30)) == DayRange(first: day(2026, 4, 1), last: day(2026, 4, 30)))
        #expect(statement(on: 31, holding: day(2026, 5, 1)) == DayRange(first: day(2026, 5, 1), last: day(2026, 5, 31)))
    }

    @Test(arguments: [(2026, 28), (2028, 29)])
    func aStatementOnThe31stClosesFebruaryOnItsLastDay(year: Int, lastDay: Int) {
        let february = DayRange(first: day(year, 2, 1), last: day(year, 2, lastDay))

        #expect(statement(on: 31, holding: day(year, 2, lastDay)) == february)
        #expect(statement(on: 31, holding: day(year, 3, 1)).first == day(year, 3, 1))
    }

    @Test func aStatementOnThe30thTakesTheLastDayOfJanuaryIntoFebruarysPeriod() {
        #expect(statement(on: 30, holding: day(2026, 1, 31)) == DayRange(first: day(2026, 1, 31), last: day(2026, 2, 28)))
        #expect(statement(on: 30, holding: day(2026, 3, 1)) == DayRange(first: day(2026, 3, 1), last: day(2026, 3, 30)))
    }

    @Test func aStatementOnThe29thClosesOnFebruary29OnlyInALeapYear() {
        #expect(statement(on: 29, holding: day(2026, 2, 28)) == DayRange(first: day(2026, 1, 30), last: day(2026, 2, 28)))
        #expect(statement(on: 29, holding: day(2026, 3, 1)) == DayRange(first: day(2026, 3, 1), last: day(2026, 3, 29)))
        #expect(statement(on: 29, holding: day(2028, 2, 29)) == DayRange(first: day(2028, 1, 30), last: day(2028, 2, 29)))
        #expect(statement(on: 29, holding: day(2028, 3, 1)) == DayRange(first: day(2028, 3, 1), last: day(2028, 3, 29)))
    }

    @Test func aStatementPeriodCanRunAcrossTheYearEnd() {
        let period = DayRange(first: day(2026, 12, 16), last: day(2027, 1, 15))

        #expect(statement(on: 15, holding: day(2026, 12, 20)) == period)
        #expect(statement(on: 15, holding: day(2027, 1, 10)) == period)
    }

    @Test func steppingBackGoesToThePreviousStatementPeriod() {
        let october = CardPeriod(containing: today, statementDay: 15)

        #expect(october.adding(-1).days == DayRange(first: day(2026, 8, 16), last: day(2026, 9, 15)))
        #expect(october.adding(-10).days == DayRange(first: day(2025, 11, 16), last: day(2025, 12, 15)))
        #expect(october.adding(-1).adding(1) == october)
    }

    @Test func steppingBackFromMarchWithAStatementOnThe31stGoesToAllOfFebruary() {
        let march = CardPeriod(containing: day(2026, 3, 9), statementDay: 31)

        #expect(march.adding(-1).days == DayRange(first: day(2026, 2, 1), last: day(2026, 2, 28)))
    }

    @Test(arguments: 1...31)
    func statementPeriodsFollowOneAnotherWithNoGapOrOverlap(statementDay: Int) {
        // Two years across a leap February, starting on New Year's Day.
        var period = CardPeriod(containing: day(2027, 1, 1), statementDay: statementDay)
        for _ in 0..<24 {
            let next = period.adding(1)
            #expect(next.firstDay == period.lastDay.adding(days: 1))
            period = next
        }

        var current = day(2027, 1, 1)
        while current < day(2029, 1, 1) {
            #expect(CardPeriod(containing: current, statementDay: statementDay).contains(current))
            current = current.adding(days: 1)
        }
    }

    // MARK: Calendar months

    @Test func withoutAStatementDateAPeriodIsTheWholeCalendarMonthEvenThisMonth() {
        let thisMonth = CardPeriod(containing: today, statementDay: nil)

        #expect(thisMonth.days == DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31)))
        #expect(!thisMonth.isStatement)
    }

    @Test(arguments: [(2026, 28), (2028, 29)])
    func withoutAStatementDateFebruaryEndsOnItsLastDay(year: Int, lastDay: Int) {
        let february = CardPeriod(containing: day(year, 2, 14), statementDay: nil)

        #expect(february.days == DayRange(first: day(year, 2, 1), last: day(year, 2, lastDay)))
    }

    @Test func withoutAStatementDateSteppingBackGoesToThePreviousMonth() {
        let january = CardPeriod(containing: day(2027, 1, 31), statementDay: nil)

        #expect(january.adding(-1).days == DayRange(first: day(2026, 12, 1), last: day(2026, 12, 31)))
    }

    // MARK: Titles

    @Test func aStatementPeriodIsNamedByItsDays() {
        let october = CardPeriod(containing: today, statementDay: 15)

        #expect(october.title(today: today, locale: unitedStates) == "09/16 – 10/15/2026")
        #expect(october.title(today: today, locale: Locale(identifier: "en_GB")) == "16/09 – 15/10/2026")
        #expect(october.adding(3).title(today: today, locale: unitedStates) == "12/16/2026 – 01/15/2027")
    }

    @Test func aCalendarMonthIsNamedAsTheTransactionsStripNamesIt() {
        let thisMonth = CardPeriod(containing: today, statementDay: nil)

        #expect([0, -1, -2].map { thisMonth.adding($0).title(today: today) } == ["This month", "Last month", "08/2026"])
    }
}
