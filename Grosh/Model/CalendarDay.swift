import Foundation

/// A calendar day with no time of day, such as a transaction's date.
nonisolated struct CalendarDay: Hashable, Sendable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// The day as `yyyymmdd`, e.g. `20261009`. Stored values sort in calendar order,
    /// so the store can sort and filter by day without knowing about time zones.
    var storedValue: Int {
        year * 10_000 + month * 100 + day
    }

    init(storedValue: Int) {
        self.init(year: storedValue / 10_000, month: storedValue / 100 % 100, day: storedValue % 100)
    }
}
