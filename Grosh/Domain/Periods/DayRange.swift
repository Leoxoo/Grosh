/// A run of calendar days, both ends included. A missing end leaves that side open.
nonisolated struct DayRange: Hashable, Sendable {
    /// The first day, or `nil` to reach back to the very beginning.
    var first: CalendarDay?
    /// The last day, or `nil` to run on with no end.
    var last: CalendarDay?

    func contains(_ day: CalendarDay) -> Bool {
        (first.map { $0 <= day } ?? true) && (last.map { day <= $0 } ?? true)
    }
}
