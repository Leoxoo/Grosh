/// The gray line a Month graph tab compares its month with: the Average, or Last year while the tab's "vs last year"
/// switch is on. Either is the mean of the running totals of other months, each laid out across the month shown so that
/// months of different lengths line up.
///
/// The Average takes up to three complete months before the month shown. Months count from the month of the first
/// transaction that counts on the Month graph, on either tab: a partial first month counts, a month before it doesn't,
/// and a counted month with nothing for the tab counts as zero. The month shown is never part of its own Average.
///
/// Last year takes the same month 12 months before the month shown, and only when it holds something that counts for
/// the tab: a month with nothing for the tab is no comparison, and neither is a month before the first transaction
/// that counts.
enum MonthGraphComparison {
    case average
    case lastYear

    /// The most complete months the Average is taken over.
    static let averageMonthCount = 3

    /// What the legend and the popup call the gray line.
    var name: String {
        switch self {
        case .average: String(localized: "Average")
        case .lastYear: String(localized: "Last year")
        }
    }

    /// The comparison of `side` through the end of each day of `month`, the 1st first, from `counted`, everything that
    /// counts on the Month graph; or `nil` when no month counts toward it.
    func dailyTotals(_ side: SpentOrIncome, of counted: [CountedAmount], for month: CalendarMonth) -> [DailyTotal]? {
        let months = self.months(side, of: counted, for: month)
        guard !months.isEmpty else { return nil }
        let monthsCents = months.map { earlier in
            counted.dailyTotals(side, in: earlier, through: earlier.lastDay).map { $0.total.cents }
        }
        let dayCount = month.dayCount
        return (1...dayCount).map { number in
            let sum = monthsCents.reduce(0) { $0 + Self.stretchedCents($1, atEndOfDay: number, of: dayCount) }
            let cents = Int((Double(sum) / Double(monthsCents.count * dayCount)).rounded())
            return DailyTotal(day: month.day(number), total: Money(cents: cents))
        }
    }

    /// The months whose mean the comparison of `side` is for `month`, from `counted`.
    private func months(
        _ side: SpentOrIncome, of counted: [CountedAmount], for month: CalendarMonth
    ) -> [CalendarMonth] {
        switch self {
        case .average:
            guard let firstDay = counted.firstDay else { return [] }
            let firstMonth = CalendarMonth(firstDay)
            return (1...Self.averageMonthCount).map { month.adding(months: -$0) }.filter { $0 >= firstMonth }
        case .lastYear:
            // A month holding something that counts is never before the month of the first transaction that counts.
            let lastYear = month.adding(months: -12)
            return counted.contains { $0.side == side && CalendarMonth($0.day) == lastYear } ? [lastYear] : []
        }
    }

    /// The total at the end of `day` of a `dayCount`-day month, read off another month's running totals in cents,
    /// `dailyCents`, from the end of its 1st. That point falls `day × dailyCents.count / dayCount` of the other month's
    /// days in, on the straight line between the ends of the two days around it. It comes in `dayCount`ths of a cent,
    /// so it stays whole until the mean is taken.
    private static func stretchedCents(_ dailyCents: [Int], atEndOfDay day: Int, of dayCount: Int) -> Int {
        let reached = day * dailyCents.count
        let wholeDays = reached / dayCount
        let start = wholeDays == 0 ? 0 : dailyCents[wholeDays - 1]
        let remainder = reached % dayCount
        guard remainder > 0 else { return start * dayCount }
        return start * dayCount + (dailyCents[wholeDays] - start) * remainder
    }
}
