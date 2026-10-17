/// What the Recurring transactions still have due for a Month graph tab in the current month, which it draws as a
/// dotted line from today's point to the end of the month's last day.
///
/// It takes every Occurrence after today through the month's last day of every active schedule paid from the Total's
/// wallets, honouring each schedule's end and what has been dealt with: not only the next one Future lists for a
/// schedule that repeats forever. A varying Bill counts its estimate, and each Occurrence counts by its category as its
/// transaction would. It is a projection, computed on demand (ADR-0005): it changes no balance, report or transaction.
struct MonthGraphProjection {
    /// What is still due for the tab: the Occurrences that count toward it.
    private let scheduled: [ScheduledOccurrence]
    /// Today's total plus what is due through the end of each day, from today to the month's last day.
    let dailyTotals: [DailyTotal]

    /// What `recurring` still has due for `side` in `month` as it stands on `today`, on top of `todaysTotal`, or `nil`
    /// when `month` isn't the current month or nothing is due for the tab.
    init?(
        _ side: SpentOrIncome, of recurring: [RecurringTransaction],
        in month: CalendarMonth, today: CalendarDay, todaysTotal: Money
    ) {
        guard month == CalendarMonth(today) else { return nil }
        let scheduled = recurring
            .scheduledOccurrences(selection: .total, today: today, through: month.lastDay)
            .filter { $0.countedAmount?.side == side }
        guard !scheduled.isEmpty else { return nil }
        self.scheduled = scheduled
        dailyTotals = scheduled.compactMap(\.countedAmount).dailyTotals(side, in: month, through: month.lastDay)
            .filter { $0.day >= today }
            .map { DailyTotal(day: $0.day, total: Money(cents: todaysTotal.cents + $0.total.cents)) }
    }

    /// What is due on `day`, the most recently added schedule first.
    func occurrences(on day: CalendarDay) -> [ScheduledOccurrence] {
        scheduled.filter { $0.day == day }
    }

    /// Today's total plus what is due through the end of `day`, or `nil` until something due falls on or before it.
    func expectedTotal(through day: CalendarDay) -> Money? {
        guard scheduled.contains(where: { $0.day <= day }) else { return nil }
        return dailyTotals.total(on: day)
    }
}
