/// What the Recurring transactions still have due for a Month graph card in the current month, which it draws as a
/// dotted line from today's point to the end of the month's last day.
///
/// It takes every Occurrence after today through the month's last day of every active schedule paid from the Total's
/// wallets, honouring each schedule's end and what has been dealt with: not only the next one Future lists for a
/// schedule that repeats forever. A varying Bill counts its estimate, and each Occurrence counts by its category as its
/// transaction would. It is a projection, computed on demand (ADR-0005): it changes no balance, report or transaction.
struct MonthGraphProjection {
    /// An Occurrence still to come in the month, as the popup names it.
    struct Item: Hashable {
        /// Its Recurring transaction's name.
        let name: String
        let day: CalendarDay
        /// What it adds to the card's total.
        let amount: Money
    }

    /// What is still due for the card.
    private let scheduled: [Item]
    /// Today's total plus what is due through the end of each day, from today to the month's last day.
    let dailyTotals: [(day: CalendarDay, total: Money)]

    /// What `recurring` still has due for `side` in `month` as it stands on `today`, on top of `todaysTotal`, or `nil`
    /// when `month` isn't the current month or nothing is due for the card. `history` is what a varying Bill's estimate
    /// is averaged over.
    init?(
        _ side: SpentOrIncome, of recurring: [RecurringTransaction], history: [Transaction],
        in month: CalendarMonth, today: CalendarDay, todaysTotal: Money
    ) {
        guard month == CalendarMonth(today) else { return nil }
        let counted = recurring
            .scheduledOccurrences(selection: .total, today: today, through: month.lastDay, history: history)
            .compactMap { occurrence in
                occurrence.countedAmount.map { (name: occurrence.recurring.name, counted: $0) }
            }
            .filter { $0.counted.side == side }
        guard !counted.isEmpty else { return nil }
        scheduled = counted.map { Item(name: $0.name, day: $0.counted.day, amount: $0.counted.amount) }
        dailyTotals = counted.map { $0.counted }.dailyTotals(side, in: month, through: month.lastDay)
            .filter { $0.day >= today }
            .map { (day: $0.day, total: Money(cents: todaysTotal.cents + $0.total.cents)) }
    }

    /// What is due on `day`, the most recently added schedule first.
    func items(on day: CalendarDay) -> [Item] {
        scheduled.filter { $0.day == day }
    }

    /// Today's total plus what is due through the end of `day`, or `nil` until something due falls on or before it.
    func expectedTotal(through day: CalendarDay) -> Money? {
        guard scheduled.contains(where: { $0.day <= day }) else { return nil }
        return dailyTotals.first { $0.day == day }?.total
    }
}
