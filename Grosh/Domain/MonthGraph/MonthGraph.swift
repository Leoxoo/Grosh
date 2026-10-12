/// One card of the Month graph, Spent or Income, for a month as it stands on a day: everything the card draws and says,
/// worked out here so the card only draws it.
///
/// Its line is the month's running total, starting at zero at the start of the 1st. The end of day `d` of an `N`-day
/// month sits `d/N` of the way across, so months of different lengths span the same width. In the current month the
/// line runs through today; in an earlier month, through its last day. The gray line it is compared with, the Average
/// or Last year (``MonthGraphComparison``), runs across the whole month. In the current month, a dotted line continues
/// from today to the end of the month with what the Recurring transactions still have due (``MonthGraphProjection``).
struct MonthGraph {
    /// A point of the line: how far across the month it sits, from 0 at the start of the 1st to 1 at the end of the
    /// last day, and the running total there.
    struct Point {
        let position: Double
        let total: Money
    }

    /// What the popup says about a day of the month.
    struct Popup {
        let day: CalendarDay
        /// The running total through the end of the day, or `nil` for a day the line doesn't reach yet.
        let total: Money?
        /// The gray line's total through the end of the day, or `nil` when the card has no gray line.
        let comparison: Money?
        /// The Occurrences the Recurring transactions have due on the day, the most recently added schedule first, each
        /// adding its `countedAmount` to the card's total: only on a day after today in the current month.
        let scheduled: [ScheduledOccurrence]
        /// Today's total plus what is due through the end of the day, on a day after today once something due has
        /// fallen on or before it; otherwise `nil`.
        let expected: Money?
    }

    let side: SpentOrIncome
    let month: CalendarMonth
    /// The legend's name for the line, as the strip above the cards names the month: "This month", "Last month",
    /// "07/2026".
    let lineName: String
    /// What the gray line is, which the legend and the popup name it after: Last year when the card's switch asks for
    /// it and it is available, otherwise the Average.
    let comparison: MonthGraphComparison
    /// Whether Last year is available for the month, so the card's "vs last year" switch can be used.
    let isLastYearAvailable: Bool
    /// The running total through the end of each day the line reaches, the 1st first.
    private let dailyTotals: [DailyTotal]
    /// The gray line's total through the end of each day of the month, the 1st first, or `nil` when no month counts
    /// toward it.
    private let dailyComparisons: [DailyTotal]?
    /// What `recurring` still has due for the card this month, or `nil` in an earlier month or with nothing due.
    private let projection: MonthGraphProjection?
    private let dayCount: Int

    /// The card for `side` showing `month`, the current month or an earlier one, as it stands on `today`, with what
    /// `recurring` still has due this month, compared with `choice`, as the card's switch is set.
    init(
        _ side: SpentOrIncome, of transactions: [Transaction], recurring: [RecurringTransaction] = [],
        in month: CalendarMonth, today: CalendarDay, comparingWith choice: MonthGraphComparison = .average
    ) {
        let counted = transactions.compactMap(\.countedAmount)
        let dailyTotals = counted.dailyTotals(side, in: month, through: today)
        self.side = side
        self.month = month
        self.lineName = Period.month(month).title(today: today)
        self.dailyTotals = dailyTotals
        let lastYear = MonthGraphComparison.lastYear.dailyTotals(side, of: counted, for: month)
        self.isLastYearAvailable = lastYear != nil
        if choice == .lastYear, let lastYear {
            self.comparison = .lastYear
            self.dailyComparisons = lastYear
        } else {
            // A switch left on shows the Average while Last year isn't available, and Last year again once it is.
            self.comparison = .average
            self.dailyComparisons = MonthGraphComparison.average.dailyTotals(side, of: counted, for: month)
        }
        self.projection = MonthGraphProjection(
            side, of: recurring, history: transactions, in: month, today: today,
            todaysTotal: dailyTotals.last?.total ?? Money(cents: 0)
        )
        self.dayCount = month.dayCount
    }

    /// The line: zero at the start of the 1st, then the running total at the end of each day it reaches.
    var line: [Point] { points(dailyTotals) }

    /// The gray line: the comparison from zero at the start of the 1st to the end of the month's last day, or `nil`
    /// when no month counts toward it.
    var comparisonLine: [Point]? { dailyComparisons.map { points($0) } }

    /// The dotted line: from today's point, today's total plus what the Recurring transactions have due through the end
    /// of each day to the month's last; or `nil` in an earlier month, or when nothing is due for the card.
    var scheduledLine: [Point]? {
        projection?.dailyTotals.map { Point(position: position(of: $0.day), total: $0.total) }
    }

    /// Expected by month end: where the dotted line ends, or `nil` without one.
    var expectedByMonthEnd: Money? { projection?.dailyTotals.last?.total }

    /// The month's total so far, the card's headline: where the line ends.
    var headline: Money { dailyTotals.last?.total ?? Money(cents: 0) }

    /// The day the marker and popup are on until the user picks another: the last day the line reaches, which in the
    /// current month is today.
    var defaultSelection: CalendarDay { dailyTotals.last?.day ?? month.firstDay }

    /// Where the end of `day` sits across the month, as the line's points do.
    func position(of day: CalendarDay) -> Double {
        Double(day.day) / Double(dayCount)
    }

    /// The day of the month whose end sits nearest `position`, where the marker snaps to as the user drags across the
    /// chart: a day the line doesn't reach yet too, and the first or last day past either edge.
    func day(nearest position: Double) -> CalendarDay {
        let number = min(max(1, (position * Double(dayCount)).rounded()), Double(dayCount))
        return month.day(Int(number))
    }

    /// What the popup says about `day`.
    func popup(on day: CalendarDay) -> Popup {
        Popup(
            day: day,
            total: dailyTotals.total(on: day),
            comparison: dailyComparisons?.total(on: day),
            scheduled: projection?.occurrences(on: day) ?? [],
            expected: projection?.expectedTotal(through: day)
        )
    }

    /// Zero at the start of the 1st, then each of `daily`'s totals at the end of its day.
    private func points(_ daily: [DailyTotal]) -> [Point] {
        [Point(position: 0, total: Money(cents: 0))]
            + daily.map { Point(position: position(of: $0.day), total: $0.total) }
    }
}

extension MonthGraph {
    /// The months the strip above the cards offers, oldest first: from the month of the first transaction that counts
    /// on the Month graph, on either card, through `today`'s month, or `today`'s month alone when nothing counts.
    /// Never Future.
    static func months(of transactions: [Transaction], today: CalendarDay) -> [Period] {
        let firstDay = transactions.compactMap(\.countedAmount).firstDay
        return TimeRange.month.periods(from: firstDay, today: today).filter { $0 != .future }
    }
}

/// A Month graph card's running total through the end of a day.
struct DailyTotal {
    let day: CalendarDay
    let total: Money
}

extension Array where Element == DailyTotal {
    /// The running total through the end of `day`, or `nil` for a day these don't reach.
    func total(on day: CalendarDay) -> Money? {
        first { $0.day == day }?.total
    }
}

extension Sequence where Element == CountedAmount {
    /// The earliest day anything counts on the Month graph, on either card, or `nil` when nothing does: the day of the
    /// first transaction that counts, which the strip and the Average count months from.
    var firstDay: CalendarDay? {
        map(\.day).min()
    }

    /// The running total of what counts toward `side` in `month`, through the end of each of its days up to `lastDay`,
    /// the 1st first.
    func dailyTotals(_ side: SpentOrIncome, in month: CalendarMonth, through lastDay: CalendarDay) -> [DailyTotal] {
        var centsByDay: [CalendarDay: Int] = [:]
        for counted in self where counted.side == side && CalendarMonth(counted.day) == month {
            centsByDay[counted.day, default: 0] += counted.amount.cents
        }
        var running = 0
        var dailyTotals: [DailyTotal] = []
        for number in 1...month.dayCount {
            let day = month.day(number)
            guard day <= lastDay else { break }
            running += centsByDay[day, default: 0]
            dailyTotals.append(DailyTotal(day: day, total: Money(cents: running)))
        }
        return dailyTotals
    }
}
