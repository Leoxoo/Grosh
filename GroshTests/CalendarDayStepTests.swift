import Testing
@testable import Grosh

/// The ‹ › day steppers next to a transaction's date.
struct CalendarDayStepTests {
    @Test(arguments: [
        (CalendarDay(year: 2026, month: 10, day: 9), 1, CalendarDay(year: 2026, month: 10, day: 10)),
        (CalendarDay(year: 2026, month: 10, day: 31), 1, CalendarDay(year: 2026, month: 11, day: 1)),
        (CalendarDay(year: 2026, month: 1, day: 1), -1, CalendarDay(year: 2025, month: 12, day: 31)),
        (CalendarDay(year: 2028, month: 2, day: 28), 1, CalendarDay(year: 2028, month: 2, day: 29)),
        (CalendarDay(year: 2026, month: 3, day: 1), -1, CalendarDay(year: 2026, month: 2, day: 28)),
    ])
    func steppingMovesOneCalendarDay(from day: CalendarDay, by days: Int, to expected: CalendarDay) {
        #expect(day.adding(days: days) == expected)
    }
}
