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
