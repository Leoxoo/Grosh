import Foundation

/// One tab of the Month graph, Spent or Income, for a period as it stands on a day: everything the tab draws and says,
/// worked out here so the tab only draws it.
///
/// Its line is the period's running total, starting at zero at the start of its first day. The end of day `d` of an `N`-day
/// period sits `d/N` of the way across, so periods of different lengths span the same width. In the current period the
/// line runs through today; in an earlier one, through its last day. The gray line it is compared with, the Average or
/// Last year (``MonthGraphComparison``), runs across the whole period. In the current period, a dotted line continues from
/// today to the end of the period with what the Recurring transactions still have due (``MonthGraphProjection``).
///
/// Home's Month graph shows a month of the strip, counting the Total. The Income and Spent details' comparison shows any
/// week, month, quarter or year, counting the Wallet selector's choice.
struct MonthGraph {
    /// A point of the line: how far across the period it sits, from 0 at the start of its first day to 1 at the end of its
    /// last day, and the running total there.
    struct Point {
        let position: Double
        let total: Money
    }

    /// What the popup says about a day of the period.
    struct Popup {
        let day: CalendarDay
        /// The running total through the end of the day, or `nil` for a day the line doesn't reach yet.
        let total: Money?
        /// The gray line's total through the end of the day, or `nil` when the tab has no gray line.
        let comparison: Money?
        /// The Occurrences the Recurring transactions have due on the day, the most recently added schedule first, each
        /// adding its `countedAmount` to the tab's total: only on a day after today in the current period.
        let scheduled: [ScheduledOccurrence]
        /// Today's total plus what is due through the end of the day, on a day after today once something due has
        /// fallen on or before it; otherwise `nil`.
        let expected: Money?
    }

    let side: SpentOrIncome
    /// The period the tab shows.
    let period: Period
    /// The days the period covers, which the line runs across.
    let span: GraphSpan
    /// The legend's name for the line, as the strip above the card names the period: "This month", "Last month",
    /// "07/2026".
    let lineName: String
    /// What the gray line is, which the legend and the popup name it after: Last year when the "vs last year" switch
    /// asks for it and it is available, otherwise the Average.
    let comparison: MonthGraphComparison
    /// Whether Last year is available for the period, so the "vs last year" switch can be used.
    let isLastYearAvailable: Bool
    /// The running total through the end of each day the line reaches, the first day first.
    private let dailyTotals: [DailyTotal]
    /// The gray line's total through the end of each day of the period, the first day first, or `nil` when no period
    /// counts toward it.
    private let dailyComparisons: [DailyTotal]?
    /// What `recurring` still has due for the tab this period, or `nil` in an earlier period or with nothing due.
    private let projection: MonthGraphProjection?

    /// The tab for `side` showing `period`, as it stands on `today`, with what `recurring` still has due, compared with
    /// `choice`, as the "vs last year" switch is set, for the transactions of `selection`. `counted` holds at least what
    /// counts for `selection` in the periods the tab sums (the ``Transaction/countedAmount(in:)``s of its transactions,
    /// worked out once for both tabs; Home reads only those of the months ``MonthGraphHistory`` names), and `firstDay`
    /// is the first day anything counts, on either tab, or `nil` when nothing does.
    init(
        _ side: SpentOrIncome, of counted: [CountedAmount], countingFrom firstDay: CalendarDay?,
        recurring: [RecurringTransaction] = [], in period: Period, today: CalendarDay,
        comparingWith choice: MonthGraphComparison = .average, selection: WalletSelection = .total
    ) {
        guard let span = GraphSpan(period) else {
            preconditionFailure("A Month graph shows a day, week, month, quarter or year")
        }
        let dailyTotals = counted.dailyTotals(side, in: span, through: today)
        let lastYear = MonthGraphComparison.lastYear.dailyTotals(side, of: counted, countingFrom: firstDay, for: period)
        self.isLastYearAvailable = lastYear != nil
        if choice == .lastYear, let lastYear {
            self.comparison = .lastYear
            self.dailyComparisons = lastYear
        } else {
            // A switch left on shows the Average while Last year isn't available, and Last year again once it is.
            self.comparison = .average
            self.dailyComparisons = MonthGraphComparison.average.dailyTotals(
                side, of: counted, countingFrom: firstDay, for: period
            )
        }
        self.projection = MonthGraphProjection(
            side, of: recurring, in: span, selection: selection, today: today,
            todaysTotal: dailyTotals.last?.total ?? Money(cents: 0)
        )
        self.side = side
        self.period = period
        self.span = span
        self.lineName = period.title(today: today)
        self.dailyTotals = dailyTotals
    }

    /// The line: zero at the start of the first day, then the running total at the end of each day it reaches.
    var line: [Point] { points(dailyTotals) }

    /// The gray line: the comparison from zero at the start of the first day to the end of the period's last day, or
    /// `nil` when no period counts toward it.
    var comparisonLine: [Point]? { dailyComparisons.map { points($0) } }

    /// The dotted line: from today's point, today's total plus what the Recurring transactions have due through the end
    /// of each day to the period's last; or `nil` in an earlier period, or when nothing is due for the tab.
    var scheduledLine: [Point]? {
        projection?.dailyTotals.map { Point(position: position(of: $0.day), total: $0.total) }
    }

    /// Expected by month end: where the dotted line ends, or `nil` without one.
    var expectedByMonthEnd: Money? { projection?.dailyTotals.last?.total }

    /// The period's total so far, the tab's headline: where the line ends.
    var headline: Money { dailyTotals.last?.total ?? Money(cents: 0) }

    /// The day the marker and popup are on until the user picks another: the last day the line reaches, which in the
    /// current period is today.
    var defaultSelection: CalendarDay { dailyTotals.last?.day ?? span.first }

    /// Whether the "vs last year" switch applies: only a month has a same month of last year.
    var offersLastYear: Bool {
        if case .month = period { true } else { false }
    }

    /// How the period's end is named in the legend and the popup: "month end", "week end" and so on.
    var endName: String {
        switch period {
        case .day: String(localized: "day end")
        case .week: String(localized: "week end")
        case .month: String(localized: "month end")
        case .quarter: String(localized: "quarter end")
        case .year: String(localized: "year end")
        case .all, .custom, .future: String(localized: "end")
        }
    }

    /// Where the end of `day` sits across the period, as the line's points do.
    func position(of day: CalendarDay) -> Double {
        Double(span.number(of: day)) / Double(span.dayCount)
    }

    /// The day of the period whose end sits nearest `position`, where the marker snaps to as the user drags across the
    /// chart: a day the line doesn't reach yet too, and the first or last day past either edge.
    func day(nearest position: Double) -> CalendarDay {
        let number = min(max(1, (position * Double(span.dayCount)).rounded()), Double(span.dayCount))
        return span.day(Int(number))
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

    /// Zero at the start of the first day, then each of `daily`'s totals at the end of its day.
    private func points(_ daily: [DailyTotal]) -> [Point] {
        [Point(position: 0, total: Money(cents: 0))]
            + daily.map { Point(position: position(of: $0.day), total: $0.total) }
    }
}

extension MonthGraph {
    /// The months the strip above the card offers, oldest first: from the month of `firstDay`, the first day anything
    /// counts on the Month graph, on either tab, through `today`'s month, or `today`'s month alone when nothing counts
    /// (`nil`). Never Future.
    static func months(from firstDay: CalendarDay?, today: CalendarDay) -> [Period] {
        TimeRange.month.periods(from: firstDay, today: today).filter { $0 != .future }
    }
}

/// A Month graph tab's running total through the end of a day.
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
    /// The earliest day anything counts on the Month graph, on either tab, or `nil` when nothing does: the day of the
    /// first transaction that counts, which the strip and the Average count periods from.
    var firstDay: CalendarDay? {
        map(\.day).min()
    }

    /// The running total of what counts toward `side` in `span`, through the end of each of its days up to `lastDay`, the
    /// first day first.
    func dailyTotals(_ side: SpentOrIncome, in span: GraphSpan, through lastDay: CalendarDay) -> [DailyTotal] {
        var centsByDay: [CalendarDay: Int] = [:]
        for counted in self where counted.side == side && span.contains(counted.day) {
            centsByDay[counted.day, default: 0] += counted.amount.cents
        }
        var running = 0
        var dailyTotals: [DailyTotal] = []
        for number in 1...span.dayCount {
            let day = span.day(number)
            guard day <= lastDay else { break }
            running += centsByDay[day, default: 0]
            dailyTotals.append(DailyTotal(day: day, total: Money(cents: running)))
        }
        return dailyTotals
    }
}
