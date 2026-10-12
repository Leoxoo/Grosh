/// One card of the Month graph, Spent or Income, for a month as it stands on a day: everything the card draws and says,
/// worked out here so the card only draws it.
///
/// Its line is the month's running total, starting at zero at the start of the 1st. The end of day `d` of an `N`-day
/// month sits `d/N` of the way across, so months of different lengths span the same width. In the current month the
/// line runs through today; in an earlier month, through its last day. The gray line of the Average
/// (``MonthGraphAverage``) runs across the whole month.
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
        /// The Average through the end of the day, or `nil` when the card has no gray line.
        let average: Money?
    }

    let side: SpentOrIncome
    let month: CalendarMonth
    /// The legend's name for the line, as the strip above the cards names the month: "This month", "Last month",
    /// "07/2026".
    let lineName: String
    /// The running total through the end of each day the line reaches, the 1st first.
    private let dailyTotals: [(day: CalendarDay, total: Money)]
    /// The Average through the end of each day of the month, the 1st first, or `nil` when no month counts toward it.
    private let dailyAverages: [(day: CalendarDay, total: Money)]?
    private let dayCount: Int

    /// The card for `side` showing `month`, the current month or an earlier one, as it stands on `today`.
    init(_ side: SpentOrIncome, of transactions: [Transaction], in month: CalendarMonth, today: CalendarDay) {
        let counted = transactions.compactMap(\.countedAmount)
        self.side = side
        self.month = month
        self.lineName = Period.month(month).title(today: today)
        self.dailyTotals = counted.dailyTotals(side, in: month, through: today)
        self.dailyAverages = MonthGraphAverage.dailyTotals(side, of: counted, for: month)
        self.dayCount = month.dayCount
    }

    /// The line: zero at the start of the 1st, then the running total at the end of each day it reaches.
    var line: [Point] { points(dailyTotals) }

    /// The gray line: the Average from zero at the start of the 1st to the end of the month's last day, or `nil` when
    /// no month counts toward it.
    var averageLine: [Point]? { dailyAverages.map { points($0) } }

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
        return CalendarDay(year: month.year, month: month.month, day: Int(number))
    }

    /// What the popup says about `day`.
    func popup(on day: CalendarDay) -> Popup {
        Popup(
            day: day,
            total: dailyTotals.first { $0.day == day }?.total,
            average: dailyAverages?.first { $0.day == day }?.total
        )
    }

    /// Zero at the start of the 1st, then each of `daily`'s totals at the end of its day.
    private func points(_ daily: [(day: CalendarDay, total: Money)]) -> [Point] {
        [Point(position: 0, total: Money(cents: 0))]
            + daily.map { Point(position: position(of: $0.day), total: $0.total) }
    }
}

extension MonthGraph {
    /// The months the strip above the cards offers, oldest first: from the month of the first transaction that counts
    /// on the Month graph, on either card, through `today`'s month, or `today`'s month alone when nothing counts.
    /// Never Future.
    static func months(of transactions: [Transaction], today: CalendarDay) -> [Period] {
        let firstDay = transactions.compactMap(\.countedAmount).map(\.day).min()
        return TimeRange.month.periods(from: firstDay, today: today).filter { $0 != .future }
    }
}

extension Sequence where Element == CountedAmount {
    /// The running total of what counts toward `side` in `month`, through the end of each of its days up to `lastDay`,
    /// the 1st first.
    func dailyTotals(
        _ side: SpentOrIncome, in month: CalendarMonth, through lastDay: CalendarDay
    ) -> [(day: CalendarDay, total: Money)] {
        var centsByDay: [CalendarDay: Int] = [:]
        for counted in self where counted.side == side && CalendarMonth(counted.day) == month {
            centsByDay[counted.day, default: 0] += counted.amount.cents
        }
        var running = 0
        var dailyTotals: [(day: CalendarDay, total: Money)] = []
        for number in 1...month.dayCount {
            let day = CalendarDay(year: month.year, month: month.month, day: number)
            guard day <= lastDay else { break }
            running += centsByDay[day, default: 0]
            dailyTotals.append((day: day, total: Money(cents: running)))
        }
        return dailyTotals
    }
}
