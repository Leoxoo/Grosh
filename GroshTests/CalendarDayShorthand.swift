@testable import Grosh

/// A calendar day written short, for tests: `day(2026, 10, 12)`.
nonisolated func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
    CalendarDay(year: year, month: month, day: day)
}
