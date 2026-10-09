import Foundation

extension CalendarDay {
    /// The day `days` calendar days after this one (before it when negative), across month and year ends.
    func adding(days: Int) -> CalendarDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let start = date(in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return CalendarDay(moved, in: calendar)
    }
}
