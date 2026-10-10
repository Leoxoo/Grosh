import Foundation

/// The span of time the transaction list is showing: a month by default, or Future. The ``TimeRange`` decides which
/// periods the strip steps through.
///
/// No period of the strip but Future reaches past today: what is dated after today belongs to Future alone, so the
/// current day, week, month, quarter or year ends today. Only a custom range, which the user picks day by day,
/// may reach past today.
nonisolated enum Period: Hashable, Sendable {
    case day(CalendarDay)
    /// The seven days from `startingOn`.
    case week(startingOn: CalendarDay)
    case month(CalendarMonth)
    /// Quarter 1 (January–March) to 4 (October–December) of `year`.
    case quarter(year: Int, quarter: Int)
    case year(Int)
    /// Every transaction dated today or earlier.
    case all
    /// Exactly the days the user chose, which may reach past today.
    case custom(DayRange)
    /// Every transaction dated after today.
    case future

    /// The days the period covers on `today`.
    func days(today: CalendarDay) -> DayRange {
        switch self {
        case .day(let day):
            return DayRange(first: day, last: day)
        case .week(let first):
            return DayRange(first: first, last: min(first.adding(days: 6), today))
        case .month(let month):
            return DayRange(first: month.firstDay, last: min(month.lastDay, today))
        case .quarter(let year, let quarter):
            let firstMonth = CalendarMonth(year: year, month: quarter * 3 - 2)
            return DayRange(first: firstMonth.firstDay, last: min(firstMonth.adding(months: 2).lastDay, today))
        case .year(let year):
            return DayRange(
                first: CalendarDay(year: year, month: 1, day: 1),
                last: min(CalendarDay(year: year, month: 12, day: 31), today)
            )
        case .all:
            return DayRange(first: nil, last: today)
        case .custom(let days):
            return days
        case .future:
            return DayRange(first: today.adding(days: 1), last: nil)
        }
    }

    /// Whether the period's Ending balance is a projected balance: the period counts days after today, as Future
    /// and a custom range reaching past today do.
    func isProjected(today: CalendarDay) -> Bool {
        days(today: today).last.map { $0 > today } ?? true
    }

    /// The period's name in the strip: "This month", "Last month", "08/2026", "Future". A day is written in numbers
    /// in `locale`'s order, as `10/06/2026` in the US and `06/10/2026` in the UK; a month always as `08/2026`.
    func title(today: CalendarDay, locale: Locale = .current) -> String {
        switch self {
        case .day(let day):
            if day == today { return String(localized: "Today") }
            if day == today.adding(days: -1) { return String(localized: "Yesterday") }
            return day.numericTitle(locale)
        case .week(let first):
            let last = first.adding(days: 6)
            if (first...last).contains(today) { return String(localized: "This week") }
            if (first...last).contains(today.adding(days: -7)) { return String(localized: "Last week") }
            let start = first.year == last.year ? first.numericTitle(locale, withYear: false) : first.numericTitle(locale)
            return "\(start) – \(last.numericTitle(locale))"
        case .month(let month):
            let thisMonth = CalendarMonth(today)
            if month == thisMonth { return String(localized: "This month") }
            if month == thisMonth.adding(months: -1) { return String(localized: "Last month") }
            return String(format: "%02d/%d", month.month, month.year)
        case .quarter(let year, let quarter):
            let thisQuarter = TimeRange.quarter.period(containing: today)
            if self == thisQuarter { return String(localized: "This quarter") }
            let lastQuarter = TimeRange.quarter.period(containing: CalendarMonth(today).adding(months: -3).firstDay)
            if self == lastQuarter { return String(localized: "Last quarter") }
            return "Q\(quarter) \(year)"
        case .year(let year):
            if year == today.year { return String(localized: "This year") }
            if year == today.year - 1 { return String(localized: "Last year") }
            return String(year)
        case .all:
            return String(localized: "All time")
        case .custom(let days):
            // A custom range is picked with both ends; an open one would show "…" for the missing end.
            let first = days.first.map { $0.numericTitle(locale) } ?? "…"
            let last = days.last.map { $0.numericTitle(locale) } ?? "…"
            return "\(first) – \(last)"
        case .future:
            return String(localized: "Future")
        }
    }
}

private extension CalendarDay {
    /// The day as the strip writes it: two-digit day and month in `locale`'s order and with its separators, then the
    /// year unless `withYear` is false. `10/06/2026` in the US, `06/10/2026` in the UK.
    nonisolated func numericTitle(_ locale: Locale, withYear: Bool = true) -> String {
        let calendar = Calendar.utcGregorian
        let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .month(.twoDigits).day(.twoDigits)
        return date(in: calendar).formatted(withYear ? style.year() : style)
    }
}
