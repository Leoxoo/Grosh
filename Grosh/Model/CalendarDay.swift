import Foundation

/// A date without a time of day. Transactions happen on a day, not at a moment, so a day never shifts
/// when the device's time zone changes.
nonisolated struct CalendarDay: Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day as `yyyymmdd`, which sorts the same way days do.
    init(rawValue: Int) {
        self.init(year: rawValue / 10_000, month: rawValue / 100 % 100, day: rawValue % 100)
    }

    var rawValue: Int { year * 10_000 + month * 100 + day }
}

extension CalendarDay {
    /// The day `date` falls on in `calendar` (the user's calendar and time zone by default).
    nonisolated init(_ date: Date, in calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// The day it is now on the user's calendar.
    static var today: CalendarDay { CalendarDay(Date.now) }

    /// The start of this day in `calendar`, for date pickers and other APIs that take a `Date`.
    nonisolated func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }
}
