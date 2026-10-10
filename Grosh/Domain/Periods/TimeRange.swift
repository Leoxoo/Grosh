import Foundation

/// How long each period in the Transactions tab's strip is, chosen in its "…" menu. A month by default.
nonisolated enum TimeRange: Hashable, Sendable {
    case day
    case week
    case month
    case quarter
    case year
    /// One period holding everything through today.
    case all
    /// One period of exactly the days the user chose, which may reach past today.
    case custom(DayRange)

    /// The ranges the "…" menu offers by name, shortest first. A custom range is picked with its own dates.
    static let presets: [TimeRange] = [.day, .week, .month, .quarter, .year, .all]

    /// The range's name in the "…" menu.
    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .quarter: String(localized: "Quarter")
        case .year: String(localized: "Year")
        case .all: String(localized: "All")
        case .custom: String(localized: "Custom")
        }
    }

    /// The days picking a custom range starts with: the current custom range, or this month so far.
    func customRangeStart(today: CalendarDay) -> DayRange {
        if case .custom(let days) = self { return days }
        return DayRange(first: CalendarMonth(today).firstDay, last: today)
    }

    /// The periods the strip steps through, oldest first: one for each span from the one holding `earliest`
    /// (the first day with data) through the one holding `today`, then Future.
    ///
    /// `firstWeekday` is the day weeks start on, as `Calendar.firstWeekday` numbers them (1 is Sunday).
    func periods(
        from earliest: CalendarDay?,
        today: CalendarDay,
        firstWeekday: Int = Calendar.current.firstWeekday
    ) -> [Period] {
        if case .custom(let days) = self { return [.custom(days)] }
        var period = period(containing: min(earliest ?? today, today), firstWeekday: firstWeekday)
        var periods = [period]
        while let last = period.days(today: today).last, last < today {
            period = self.period(containing: last.adding(days: 1), firstWeekday: firstWeekday)
            periods.append(period)
        }
        return periods + [.future]
    }

    /// The period of this length that holds `day`. A custom range has only its own period, whatever `day` is.
    func period(containing day: CalendarDay, firstWeekday: Int = Calendar.current.firstWeekday) -> Period {
        switch self {
        case .day: .day(day)
        case .week: .week(startingOn: day.adding(days: -(day.weekday - firstWeekday + 7) % 7))
        case .month: .month(CalendarMonth(day))
        case .quarter: .quarter(year: day.year, quarter: (day.month - 1) / 3 + 1)
        case .year: .year(day.year)
        case .all: .all
        case .custom(let days): .custom(days)
        }
    }
}

extension CalendarDay {
    /// The day of the week, numbered as `Calendar` numbers them: 1 is Sunday, 7 is Saturday.
    nonisolated var weekday: Int {
        let calendar = Calendar.utcGregorian
        return calendar.component(.weekday, from: date(in: calendar))
    }
}
