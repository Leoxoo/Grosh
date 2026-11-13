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

    /// The month as `yyyymm`, which sorts the same way months do: how a saved month total and a dirty mark hold it
    /// (ADR-0013).
    init(rawValue: Int) {
        self.init(year: rawValue / 100, month: rawValue % 100)
    }

    var rawValue: Int { year * 100 + month }
}

nonisolated extension CalendarMonth: Comparable {
    static func < (lhs: CalendarMonth, rhs: CalendarMonth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
