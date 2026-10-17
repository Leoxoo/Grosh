/// What the Recurring transactions still have due for a Month graph tab in the current period, which it draws as a
/// dotted line from today's point to the end of the period's last day.
///
/// It takes every Occurrence after today through the period's last day of every active schedule paid from the wallets
/// the selection holds, honouring each schedule's end and what has been dealt with: not only the next one Future lists for
/// a schedule that repeats forever. A varying Bill counts its estimate, and each Occurrence counts by its category as its
/// transaction would. It is a projection, computed on demand (ADR-0005): it changes no balance, report or transaction.
struct MonthGraphProjection {
    /// What is still due for the tab: the Occurrences that count toward it.
    private let scheduled: [ScheduledOccurrence]
    /// Today's total plus what is due through the end of each day, from today to the period's last day.
    let dailyTotals: [DailyTotal]

    /// What `recurring` still has due for `side` in `span` as it stands on `today`, on top of `todaysTotal`, or `nil` when
    /// `today` isn't in the span or nothing is due for the tab. `selection` is the wallets whose Occurrences count.
    init?(
        _ side: SpentOrIncome, of recurring: [RecurringTransaction],
        in span: GraphSpan, selection: WalletSelection, today: CalendarDay, todaysTotal: Money
    ) {
        guard span.contains(today) else { return nil }
        let scheduled = recurring
            .scheduledOccurrences(selection: selection, today: today, through: span.last)
            .filter { $0.countedAmount?.side == side }
        guard !scheduled.isEmpty else { return nil }
        self.scheduled = scheduled
        dailyTotals = scheduled.compactMap(\.countedAmount).dailyTotals(side, in: span, through: span.last)
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
