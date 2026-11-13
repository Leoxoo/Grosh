import Foundation
import SwiftData

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

    /// How many days before a statement period its lead-in transactions reach back.
    static let leadInDayCount = 2

    /// The days of a statement period's lead-in transactions: the ``leadInDayCount`` days before its first day, which
    /// are the last days of the previous statement. `nil` for a calendar month, which has none.
    var leadInDays: DayRange? {
        guard isStatement else { return nil }
        return DayRange(first: firstDay.adding(days: -Self.leadInDayCount), last: firstDay.adding(days: -1))
    }

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
        day(min(statementDay, dayCount))
    }
}

extension Card {
    /// The period holding `day` that the Card's transactions are shown in: its statement period for a Credit card with
    /// a statement date, otherwise `day`'s calendar month.
    func period(containing day: CalendarDay) -> CardPeriod {
        CardPeriod(containing: day, statementDay: kind == .credit ? statementDay : nil)
    }
}

/// What a Card's statement screen shows for one period: the periods ‹ › step through, the transactions paid with the
/// Card in the period, and its lead-in transactions.
nonisolated struct CardStatement {
    /// The periods ‹ › step through, oldest first: from the one holding the Card's first transaction through the one
    /// holding `today`, or its last transaction when that is dated later.
    let periods: ClosedRange<CardPeriod>
    /// The transactions paid with the Card in the period. Their `net` is the period's total: every one counts,
    /// excluded from report or not, as on the card's statement.
    let transactions: [Transaction]
    /// The lead-in transactions: those paid with the Card in the two days before a statement period begins, since
    /// entries aren't always dated exactly as on the statement. They belong to the previous statement and never count
    /// in this one's total unless the user adds one for the moment. None for a calendar month.
    let leadIns: [Transaction]

    /// The statement of `card` for `period` on `today`, from what its ``Reads`` found in the store: `paid`, `earliest`
    /// and `latest`.
    init(
        of card: Card, for period: CardPeriod, paid: [Transaction], earliest: [Transaction], latest: [Transaction],
        today: CalendarDay
    ) {
        let leadInDays = period.leadInDays
        var transactions: [Transaction] = []
        var leadIns: [Transaction] = []
        for transaction in paid {
            let day = transaction.day
            if period.contains(day) {
                transactions.append(transaction)
            } else if leadInDays?.contains(day) == true {
                leadIns.append(transaction)
            }
        }
        let first = min(earliest.first?.day ?? today, today)
        let last = max(latest.first?.day ?? today, today)
        periods = card.period(containing: first)...card.period(containing: last)
        self.transactions = transactions
        self.leadIns = leadIns
    }
}

extension CardStatement {
    /// What the statement screen reads from the store for one period, found by the store rather than by walking every
    /// transaction the Card paid for, which run into thousands for a main Card.
    struct Reads {
        /// The Card's transactions outside Recently Deleted on the period's days and its lead-in days, if it has any.
        let paid: FetchDescriptor<Transaction>
        /// The Card's earliest transaction outside Recently Deleted, by day: where its statements' ‹ stops.
        let earliest: FetchDescriptor<Transaction>
        /// The Card's latest transaction outside Recently Deleted, by day: where its statements' › stops.
        let latest: FetchDescriptor<Transaction>

        init(card: Card, for period: CardPeriod) {
            let id = card.persistentModelID
            let firstRaw = (period.leadInDays?.first ?? period.firstDay).rawValue
            let lastRaw = period.lastDay.rawValue
            paid = FetchDescriptor(predicate: #Predicate { transaction in
                transaction.card?.persistentModelID == id && transaction.deletedAt == nil
                    && transaction.dayRaw >= firstRaw && transaction.dayRaw <= lastRaw
            })
            earliest = Self.end(of: id, order: .forward)
            latest = Self.end(of: id, order: .reverse)
        }

        private static func end(of card: PersistentIdentifier, order: SortOrder) -> FetchDescriptor<Transaction> {
            var descriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate { $0.card?.persistentModelID == card && $0.deletedAt == nil },
                sortBy: [SortDescriptor(\.dayRaw, order: order)]
            )
            descriptor.fetchLimit = 1
            return descriptor
        }
    }
}
