import Foundation

nonisolated extension CalendarMonth {
    /// The month `months` months after this one (before it when negative), across year ends.
    func adding(months: Int) -> CalendarMonth {
        let index = year * 12 + (month - 1) + months
        return CalendarMonth(year: index.floorDiv(12), month: index.floorMod(12) + 1)
    }

    /// Day `number`, 1 to `dayCount`, of the month.
    func day(_ number: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: number)
    }

    var firstDay: CalendarDay { day(1) }

    var lastDay: CalendarDay { day(dayCount) }

    /// How many days the month has: 28 to 31.
    var dayCount: Int {
        let calendar = Calendar.utcGregorian
        return calendar.range(of: .day, in: .month, for: firstDay.date(in: calendar))?.count ?? 28
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

extension CalendarMonth {
    /// The month as the strip and the Trend write it, `08/2026`, whatever the locale.
    nonisolated var numericTitle: String {
        String(format: "%02d/%d", month, year)
    }
}
