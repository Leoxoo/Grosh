import Foundation

/// The gray line a Month graph tab compares its period with: the Average, or Last year while the "vs last year" switch
/// is on. Either is the mean of the running totals of other periods, each laid out across the period shown so that
/// periods of different lengths line up.
///
/// The Average takes up to ``averagePeriodCount`` complete periods of the same length before the period shown. Periods count from the
/// period of the first transaction that counts on the Month graph, on either tab: a partial first period counts, a period
/// before it doesn't, and a counted period with nothing for the tab counts as zero. The period shown is never part of its
/// own Average.
///
/// Last year takes the same month 12 months before the month shown, and only for a month: a month with nothing for the tab
/// is no comparison, and neither is a month before the first transaction that counts.
enum MonthGraphComparison {
    case average
    case lastYear

    /// The most complete periods the Average is taken over: weeks, months, quarters or years, as the period shown is.
    static let averagePeriodCount = 3

    /// The months the comparisons of `month` read, oldest first: Last year's month, then the Average's months. Home
    /// reads the store for these and `month` alone (``MonthGraphHistory``).
    static func monthsRead(for month: CalendarMonth) -> [CalendarMonth] {
        let averaged = averagedPeriods(before: .month(month)).compactMap { period -> CalendarMonth? in
            guard case .month(let month) = period else { return nil }
            return month
        }
        return [lastYear(of: month)] + averaged.reversed()
    }

    /// The month Last year compares `month` with: the same month a year before.
    private static func lastYear(of month: CalendarMonth) -> CalendarMonth {
        month.adding(months: -12)
    }

    /// The ``averagePeriodCount`` periods of `period`'s length before it, the latest first, whether or not they count.
    /// They are laid out as `period` is, so they line up with it whatever the calendar's first weekday is.
    private static func averagedPeriods(before period: Period) -> [Period] {
        guard let timeRange = period.timeRange, let shownStart = GraphSpan(period)?.first else { return [] }
        var periods: [Period] = []
        var earlier = period
        for _ in 1...averagePeriodCount {
            guard let start = GraphSpan(earlier)?.first else { break }
            earlier = timeRange.period(containing: start.adding(days: -1), firstWeekday: shownStart.weekday)
            periods.append(earlier)
        }
        return periods
    }

    /// What the legend and the popup call the gray line.
    var name: String {
        switch self {
        case .average: String(localized: Strings.Home.average)
        case .lastYear: String(localized: Strings.Periods.lastYear)
        }
    }

    /// The comparison of `side` through the end of each day of `period`, the first day first, from `counted`, which holds
    /// at least what counts in the periods it compares with; or `nil` when no period counts toward it. `firstDay` is the
    /// first day anything counts on the Month graph, on either tab, or `nil` when nothing does. In `currencyCode`.
    func dailyTotals(
        _ side: SpentOrIncome, of counted: [CountedAmount], countingFrom firstDay: CalendarDay?, for period: Period,
        currencyCode: String
    ) -> [DailyTotal]? {
        guard let span = GraphSpan(period) else { return nil }
        let spans = earlierSpans(side, of: counted, countingFrom: firstDay, for: period)
        guard !spans.isEmpty else { return nil }
        let spansCents = spans.map { earlier in
            counted.dailyTotals(side, in: earlier, through: earlier.last, currencyCode: currencyCode).map(\.total.cents)
        }
        let dayCount = span.dayCount
        return (1...dayCount).map { number in
            let sum = spansCents.reduce(0) { $0 + Self.stretchedCents($1, atEndOfDay: number, of: dayCount) }
            let cents = Int((Double(sum) / Double(spansCents.count * dayCount)).rounded())
            return DailyTotal(day: span.day(number), total: Money(cents: cents, currencyCode: currencyCode))
        }
    }

    /// The earlier periods whose mean the comparison of `side` is for `period`, from `counted`.
    private func earlierSpans(
        _ side: SpentOrIncome, of counted: [CountedAmount], countingFrom firstDay: CalendarDay?, for period: Period
    ) -> [GraphSpan] {
        switch self {
        case .average:
            guard let firstDay, let timeRange = period.timeRange, let shownStart = GraphSpan(period)?.first
            else { return [] }
            let firstCounted = timeRange.period(containing: firstDay, firstWeekday: shownStart.weekday)
            guard let firstCountedStart = GraphSpan(firstCounted)?.first else { return [] }
            // Each earlier period is before the last, so once one is before the first that counts, the rest are too.
            return Array(
                Self.averagedPeriods(before: period).compactMap { GraphSpan($0) }.prefix { $0.first >= firstCountedStart }
            )
        case .lastYear:
            // Only a month has a same month of last year, and it is there only when it holds something that counts.
            guard case .month(let month) = period else { return [] }
            let lastYear = Self.lastYear(of: month)
            guard counted.contains(where: { $0.side == side && CalendarMonth($0.day) == lastYear }),
                  let span = GraphSpan(.month(lastYear))
            else { return [] }
            return [span]
        }
    }

    /// The total at the end of `day` of a `dayCount`-day period, read off another period's running totals in cents,
    /// `dailyCents`, from the end of its first day. That point falls `day × dailyCents.count / dayCount` of the other
    /// period's days in, on the straight line between the ends of the two days around it. It comes in `dayCount`ths of a
    /// cent, so it stays whole until the mean is taken.
    private static func stretchedCents(_ dailyCents: [Int], atEndOfDay day: Int, of dayCount: Int) -> Int {
        let reached = day * dailyCents.count
        let wholeDays = reached / dayCount
        let start = wholeDays == 0 ? 0 : dailyCents[wholeDays - 1]
        let remainder = reached % dayCount
        guard remainder > 0 else { return start * dayCount }
        return start * dayCount + (dailyCents[wholeDays] - start) * remainder
    }
}
