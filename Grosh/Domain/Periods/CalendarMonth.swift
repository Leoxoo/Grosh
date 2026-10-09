import Foundation

/// A month of a year, such as 08/2026.
nonisolated struct CalendarMonth: Hashable, Sendable {
    let year: Int
    /// 1–12.
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    /// The month `day` falls in.
    init(_ day: CalendarDay) {
        self.init(year: day.year, month: day.month)
    }

    /// The month `months` months after this one (before it when negative), across year ends.
    func adding(months: Int) -> CalendarMonth {
        let index = year * 12 + (month - 1) + months
        return CalendarMonth(year: index.floorDiv(12), month: index.floorMod(12) + 1)
    }

    var firstDay: CalendarDay { CalendarDay(year: year, month: month, day: 1) }

    var lastDay: CalendarDay {
        CalendarDay(year: year, month: month, day: Self.gregorian.range(of: .day, in: .month, for: firstDay.date(in: Self.gregorian))?.count ?? 28)
    }

    private static let gregorian: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()
}

/// Months compare in calendar order.
nonisolated extension CalendarMonth: Comparable {
    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

private extension Int {
    /// Division rounding toward negative infinity.
    nonisolated func floorDiv(_ divisor: Int) -> Int {
        (self - floorMod(divisor)) / divisor
    }

    /// The remainder that is never negative.
    nonisolated func floorMod(_ divisor: Int) -> Int {
        ((self % divisor) + divisor) % divisor
    }
}
