import Foundation
import Testing
@testable import Grosh

struct CalendarDayConversionTests {
    private let newYork: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    @Test func aMomentFallsOnItsLocalCalendarDay() throws {
        // 03:30 UTC on Oct 10 is still the evening of Oct 9 in New York.
        let lateEvening = try Date("2026-10-10T03:30:00Z", strategy: .iso8601)

        #expect(CalendarDay(lateEvening, in: newYork) == CalendarDay(year: 2026, month: 10, day: 9))
    }

    @Test func aDayTurnsIntoTheStartOfThatDay() throws {
        let day = CalendarDay(year: 2026, month: 3, day: 8)

        #expect(day.date(in: newYork) == (try Date("2026-03-08T05:00:00Z", strategy: .iso8601)))
    }
}
