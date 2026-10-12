/// One card of the Month graph, Spent or Income, for a month as it stands on a day: everything the card draws and says,
/// worked out here so the card only draws it.
///
/// Its line is the month's running total, starting at zero at the start of the 1st. The end of day `d` of an `N`-day
/// month sits `d/N` of the way across, so months of different lengths span the same width. In the current month the
/// line runs through today; in an earlier month, through its last day.
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
    }

    let side: SpentOrIncome
    let month: CalendarMonth
    /// The running total through the end of each day the line reaches, the 1st first.
    private let dailyTotals: [(day: CalendarDay, total: Money)]
    private let dayCount: Int

    /// The card for `side` showing `month`, the current month or an earlier one, as it stands on `today`.
    init(_ side: SpentOrIncome, of transactions: [Transaction], in month: CalendarMonth, today: CalendarDay) {
        var centsByDay: [CalendarDay: Int] = [:]
        for counted in transactions.compactMap(\.countedAmount)
        where counted.side == side && CalendarMonth(counted.day) == month {
            centsByDay[counted.day, default: 0] += counted.amount.cents
        }
        let dayCount = month.dayCount
        var running = 0
        var dailyTotals: [(day: CalendarDay, total: Money)] = []
        for number in 1...dayCount {
            let day = CalendarDay(year: month.year, month: month.month, day: number)
            guard day <= today else { break }
            running += centsByDay[day, default: 0]
            dailyTotals.append((day: day, total: Money(cents: running)))
        }
        self.side = side
        self.month = month
        self.dailyTotals = dailyTotals
        self.dayCount = dayCount
    }

    /// The line: zero at the start of the 1st, then the running total at the end of each day it reaches.
    var line: [Point] {
        [Point(position: 0, total: Money(cents: 0))]
            + dailyTotals.map { Point(position: position(of: $0.day), total: $0.total) }
    }

    /// The month's total so far, the card's headline: where the line ends.
    var headline: Money { dailyTotals.last?.total ?? Money(cents: 0) }

    /// The day the marker and popup are on until the user picks another: the last day the line reaches, which in the
    /// current month is today.
    var defaultSelection: CalendarDay { dailyTotals.last?.day ?? month.firstDay }

    /// Where the end of `day` sits across the month, as the line's points do.
    func position(of day: CalendarDay) -> Double {
        Double(day.day) / Double(dayCount)
    }

    /// What the popup says about `day`.
    func popup(on day: CalendarDay) -> Popup {
        Popup(day: day, total: dailyTotals.first { $0.day == day }?.total)
    }
}
