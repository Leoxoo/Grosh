import Foundation

/// The span of days a Card's transactions are shown in when the user taps the Card: a statement period for a Credit
/// card with a statement date, a calendar month for any other Card.
///
/// A statement period runs from the day after one statement date through the next, both included, and is named by
/// the month it closes in: with a statement on the 15th, October's runs 09/16–10/15. A statement date of 29–31 falls
/// on the month's last day in shorter months, so with a statement on the 31st, February's closes on 02/28 and March's
/// runs 03/01–03/31.
///
/// Unlike the Transactions tab's periods, a Card's period isn't cut short at today: the current statement runs
/// through its next statement date, and the current month through its last day.
nonisolated struct CardPeriod: Hashable, Sendable {
    /// The month the period ends in: the calendar month itself, or the month the statement closes in.
    let month: CalendarMonth
    /// The day of the month the statement closes (1–31), or `nil` for calendar months.
    let statementDay: Int?

    init(month: CalendarMonth, statementDay: Int?) {
        self.month = month
        self.statementDay = statementDay
    }

    /// The period holding `day`: the statement period closing on `day` or the next statement date after it, or
    /// `day`'s month.
    init(containing day: CalendarDay, statementDay: Int?) {
        let month = CalendarMonth(day)
        let closesNextMonth = statementDay.map { day > month.statementClosingDay($0) } ?? false
        self.init(month: closesNextMonth ? month.adding(months: 1) : month, statementDay: statementDay)
    }

    /// Whether the period runs between two statement dates rather than over a calendar month.
    var isStatement: Bool { statementDay != nil }

    /// The period's first day: the day after the previous statement date, or the month's first day.
    var firstDay: CalendarDay {
        guard let statementDay else { return month.firstDay }
        return month.adding(months: -1).statementClosingDay(statementDay).adding(days: 1)
    }

    /// The period's last day: its statement date, or the month's last day.
    var lastDay: CalendarDay {
        guard let statementDay else { return month.lastDay }
        return month.statementClosingDay(statementDay)
    }

    /// The days the period covers, both ends included.
    var days: DayRange { DayRange(first: firstDay, last: lastDay) }

    func contains(_ day: CalendarDay) -> Bool {
        firstDay <= day && day <= lastDay
    }

    /// The period `count` periods after this one (before it when negative), with the same statement date.
    func adding(_ count: Int) -> CardPeriod {
        CardPeriod(month: month.adding(months: count), statementDay: statementDay)
    }

    /// The period's name: a statement period by its days in numbers, as `09/16 – 10/15/2026` in the US; a calendar
    /// month as the Transactions tab's strip names it: "This month", "Last month", "08/2026".
    func title(today: CalendarDay, locale: Locale = .current) -> String {
        guard isStatement else { return Period.month(month).title(today: today, locale: locale) }
        return firstDay.numericTitle(through: lastDay, locale: locale)
    }
}

/// A Card's periods compare in calendar order. Only periods with the same statement date (one Card's) are compared.
nonisolated extension CardPeriod: Comparable {
    static func < (lhs: CardPeriod, rhs: CardPeriod) -> Bool {
        lhs.month < rhs.month
    }
}

extension CalendarMonth {
    /// The day a statement closing on `statementDay` (1–31) closes in this month: that day, or the month's last day
    /// when the month is shorter, as 02/28 for a statement on the 31st.
    nonisolated func statementClosingDay(_ statementDay: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: min(statementDay, dayCount))
    }
}

extension Card {
    /// The period holding `day` that the Card's transactions are shown in: its statement period for a Credit card with
    /// a statement date, otherwise `day`'s calendar month.
    func period(containing day: CalendarDay) -> CardPeriod {
        CardPeriod(containing: day, statementDay: kind == .credit ? statementDay : nil)
    }

    /// The periods ‹ › step through, oldest first: from the one holding the Card's first transaction through the one
    /// holding `today`, or its last transaction when that is dated later.
    func periods(today: CalendarDay) -> ClosedRange<CardPeriod> {
        let days = (transactions ?? []).map(\.day)
        return period(containing: min(days.min() ?? today, today))...period(containing: max(days.max() ?? today, today))
    }

    /// The transactions paid with this Card in `period`. Their `net` is the period's total: every one counts,
    /// excluded from report or not, as on the card's statement.
    func transactions(in period: CardPeriod) -> [Transaction] {
        (transactions ?? []).filter { period.contains($0.day) }
    }
}
