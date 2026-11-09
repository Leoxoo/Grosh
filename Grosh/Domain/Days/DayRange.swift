import Foundation

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

extension DayRange {
    /// How many days the range covers, both ends included, or `nil` when either end is open.
    var dayCount: Int? {
        guard let first, let last else { return nil }
        let calendar = Calendar.utcGregorian
        let between = calendar.dateComponents([.day], from: first.date(in: calendar), to: last.date(in: calendar)).day ?? 0
        return between + 1
    }
}
