import Foundation
import Testing
@testable import Grosh

struct CalendarDayTests {
    @Test func aDateBelongsToTheDayInTheUsersOwnTimeZone() throws {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        // 23:30 in New York on Oct 9 is already Oct 10 in UTC.
        let lateEvening = try #require(newYork.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 23, minute: 30)))

        #expect(CalendarDay(lateEvening, calendar: newYork) == CalendarDay(year: 2026, month: 10, day: 9))
    }

    @Test func storedValuesKeepCalendarOrder() throws {
        let days = [
            CalendarDay(year: 2025, month: 12, day: 31),
            CalendarDay(year: 2026, month: 1, day: 1),
            CalendarDay(year: 2026, month: 9, day: 30),
            CalendarDay(year: 2026, month: 10, day: 1),
            CalendarDay(year: 2026, month: 10, day: 9),
        ]
        let stored = days.map(\.storedValue)

        #expect(stored == stored.sorted())
        #expect(stored.map(CalendarDay.init(storedValue:)) == days)
    }
}
