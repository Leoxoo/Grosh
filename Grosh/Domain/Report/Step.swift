import Foundation

/// One Step of a Net income or Trend screen: a unit of time, cut at the span it was split from and at today. Its unit is
/// what its name counts in: a day, a week, a calendar month, a quarter or a year.
struct Step: Hashable {
    enum Unit: Hashable {
        case day
        case week
        case month
        case quarter
        case year
    }

    let unit: Unit
    /// The first and last day the Step covers, both included.
    let first: CalendarDay
    let last: CalendarDay

    var days: DayRange { DayRange(first: first, last: last) }

    func contains(_ day: CalendarDay) -> Bool {
        days.contains(day)
    }

    /// Named the way the screens write a Step: `1–4` for days within one month, `08/2026` for a month, `Q3/2025` for a
    /// quarter, `2026` for a year, and a single day in numbers. Any other span is written in numbers, as `10/26 – 11/01/2026`.
    func title(locale: Locale = .current) -> String {
        switch unit {
        case .day:
            return first.numericTitle(locale)
        case .week:
            if first == last { return first.numericTitle(locale) }
            if first.month == last.month && first.year == last.year { return "\(first.day)–\(last.day)" }
            return first.numericTitle(through: last, locale: locale)
        case .month:
            return String(format: "%02d/%d", first.month, first.year)
        case .quarter:
            return "Q\((first.month - 1) / 3 + 1)/\(first.year)"
        case .year:
            return String(first.year)
        }
    }
}

extension Step {
    /// The Steps a span of `days` is split into on a screen showing `timeRange`, oldest first, each cut at the span's
    /// edges and at `today`. A day or week of a Week or Day range is a Step per day; a Month range splits into weeks
    /// starting on `firstWeekday` (as `Calendar.firstWeekday` numbers them), a Quarter or Year range into months, and
    /// All time or a custom range by its length (``unit(for:)``).
    static func steps(
        for timeRange: TimeRange, over days: DayRange, today: CalendarDay,
        firstWeekday: Int = Calendar.current.firstWeekday
    ) -> [Step] {
        guard let first = days.first else { return [] }
        let last = min(days.last ?? today, today)
        guard first <= last else { return [] }
        let unit: Unit
        switch timeRange {
        case .day, .week: unit = .day
        case .month: unit = .week
        case .quarter, .year: unit = .month
        case .all, .custom: unit = self.unit(for: DayRange(first: first, last: last))
        }
        return steps(of: unit, from: first, through: last, firstWeekday: firstWeekday)
    }

    /// The unit a span of All time or a custom range is split by, by its length: days for up to 31 days, weeks for under 3
    /// months, months for under 12, quarters for under 3 years, and years beyond that. A span is under a length when the
    /// day after its last falls before that length from its first day, so a span of exactly 3 months splits into months.
    static func unit(for span: DayRange) -> Unit {
        guard let first = span.first, let last = span.last else { return .year }
        if dayCount(from: first, through: last) <= 31 { return .day }
        let end = last.adding(days: 1)
        if end < first.adding(months: 3) { return .week }
        if end < first.adding(months: 12) { return .month }
        if end < first.adding(months: 36) { return .quarter }
        return .year
    }

    private static func steps(
        of unit: Unit, from first: CalendarDay, through last: CalendarDay, firstWeekday: Int
    ) -> [Step] {
        var steps: [Step] = []
        var start = first
        while start <= last {
            let end = min(unitEnd(of: unit, containing: start, firstWeekday: firstWeekday), last)
            steps.append(Step(unit: unit, first: start, last: end))
            start = end.adding(days: 1)
        }
        return steps
    }

    /// The last day of the `unit` that holds `day`.
    private static func unitEnd(of unit: Unit, containing day: CalendarDay, firstWeekday: Int) -> CalendarDay {
        switch unit {
        case .day:
            day
        case .week:
            day.adding(days: 6 - (day.weekday - firstWeekday + 7) % 7)
        case .month:
            CalendarMonth(day).lastDay
        case .quarter:
            CalendarMonth(year: day.year, month: ((day.month - 1) / 3) * 3 + 3).lastDay
        case .year:
            CalendarDay(year: day.year, month: 12, day: 31)
        }
    }

    private static func dayCount(from first: CalendarDay, through last: CalendarDay) -> Int {
        let calendar = Calendar.utcGregorian
        let between = calendar.dateComponents([.day], from: first.date(in: calendar), to: last.date(in: calendar)).day ?? 0
        return between + 1
    }
}

private extension CalendarDay {
    /// The day `months` months after this one, on the same day of the month, or the last day of a shorter month.
    func adding(months: Int) -> CalendarDay {
        let calendar = Calendar.utcGregorian
        let later = calendar.date(byAdding: .month, value: months, to: date(in: calendar)) ?? date(in: calendar)
        return CalendarDay(later, in: calendar)
    }
}
