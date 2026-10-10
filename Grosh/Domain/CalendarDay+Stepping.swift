import Foundation

extension Calendar {
    /// The Gregorian calendar in UTC, for arithmetic on ``CalendarDay``s: no time zone or daylight saving change
    /// can move a day.
    nonisolated static let utcGregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

extension CalendarDay {
    /// The day `days` calendar days after this one (before it when negative), across month and year ends.
    nonisolated func adding(days: Int) -> CalendarDay {
        let calendar = Calendar.utcGregorian
        let start = date(in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return CalendarDay(moved, in: calendar)
    }
}
