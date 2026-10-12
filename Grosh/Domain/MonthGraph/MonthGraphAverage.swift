/// The Average a Month graph card compares its month with: the mean of the running totals of up to three complete
/// months before it, each laid out across the month shown so that months of different lengths line up.
///
/// Months count from the month of the first transaction that counts on the Month graph, on either card: a partial first
/// month counts, a month before it doesn't, and a counted month with nothing for the card counts as zero. The month
/// shown is never part of its own Average.
enum MonthGraphAverage {
    /// The most complete months the Average is taken over.
    static let monthCount = 3

    /// The Average of `side` through the end of each day of `month`, the 1st first, from `counted`, everything that
    /// counts on the Month graph; or `nil` when no month counts toward it.
    static func dailyTotals(
        _ side: SpentOrIncome, of counted: [CountedAmount], for month: CalendarMonth
    ) -> [(day: CalendarDay, total: Money)]? {
        guard let firstDay = counted.map(\.day).min() else { return nil }
        let firstMonth = CalendarMonth(firstDay)
        let months = (1...monthCount).map { month.adding(months: -$0) }.filter { $0 >= firstMonth }
        guard !months.isEmpty else { return nil }
        let monthsCents = months.map { earlier in
            counted.dailyTotals(side, in: earlier, through: earlier.lastDay).map { $0.total.cents }
        }
        let dayCount = month.dayCount
        return (1...dayCount).map { number in
            let sum = monthsCents.reduce(0) { $0 + stretchedCents($1, atEndOfDay: number, of: dayCount) }
            let cents = Int((Double(sum) / Double(monthsCents.count * dayCount)).rounded())
            return (day: CalendarDay(year: month.year, month: month.month, day: number), total: Money(cents: cents))
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
