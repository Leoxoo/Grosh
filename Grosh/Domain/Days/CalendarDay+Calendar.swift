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

nonisolated extension CalendarDay: Comparable {
    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

nonisolated extension CalendarDay {
    /// The day `days` calendar days after this one (before it when negative), across month and year ends.
    func adding(days: Int) -> CalendarDay {
        let calendar = Calendar.utcGregorian
        let start = date(in: calendar)
        let moved = calendar.date(byAdding: .day, value: days, to: start) ?? start
        return CalendarDay(moved, in: calendar)
    }

    /// The day `months` months after this one, on the same day of the month, or the last day of a shorter month.
    func adding(months: Int) -> CalendarDay {
        let calendar = Calendar.utcGregorian
        let later = calendar.date(byAdding: .month, value: months, to: date(in: calendar)) ?? date(in: calendar)
        return CalendarDay(later, in: calendar)
    }

    /// The day of the week, numbered as `Calendar` numbers them: 1 is Sunday, 7 is Saturday.
    var weekday: Int {
        let calendar = Calendar.utcGregorian
        return calendar.component(.weekday, from: date(in: calendar))
    }
}

nonisolated extension CalendarDay {
    /// The day as the strip writes it: two-digit day and month in `locale`'s order and with its separators, then the
    /// year unless `withYear` is false. `10/06/2026` in the US, `06/10/2026` in the UK.
    func numericTitle(_ locale: Locale, withYear: Bool = true) -> String {
        let calendar = Calendar.utcGregorian
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.twoDigits).day(.twoDigits)
        return date(in: calendar).formatted(withYear ? style.year() : style)
    }

    /// The days from this one through `last` as the strip writes a span: `09/21 – 09/27/2026`, naming the first
    /// day's year too only when the two differ, as in `12/29/2025 – 01/04/2026`.
    func numericTitle(through last: CalendarDay, locale: Locale) -> String {
        let start = year == last.year ? numericTitle(locale, withYear: false) : numericTitle(locale)
        return "\(start) – \(last.numericTitle(locale))"
    }
}
