/// What counts on the Month graph and in the Report for one wallet selection, worked out once for a screen: each
/// transaction's ``Transaction/countedAmount(in:otherIncome:)``, and the first day anything counts, on either side.
/// Every figure a Report screen shows, its strip, its Month graph and its lists, comes from it, so they all count alike.
///
/// The Report builds it from every transaction outside Recently Deleted. Home's Month graph builds it from the few months
/// it reads (``MonthGraphHistory``), with the first day read from the store on its own.
struct CountedHistory {
    let selection: WalletSelection
    /// The currency every figure is written in: the selection's (``WalletSelection/currencyCode(among:)``).
    let currencyCode: String
    /// What counts, one for each of `transactions`, in no particular order.
    let counted: [CountedAmount]
    /// The first day anything counts, on either side, or `nil` when nothing does: where the strip starts, the Average
    /// counts periods from, and All time begins.
    let firstDay: CalendarDay?
    /// The transaction each of `counted` is from.
    private let transactions: [Transaction]

    /// Everything `transactions` count for `selection`, in `currencyCode`. An Expense paid back beyond its amount
    /// counts the extra under `otherIncome`.
    init(_ transactions: [Transaction], in selection: WalletSelection, currencyCode: String, otherIncome: Category) {
        self.init(
            transactions, selection: selection, currencyCode: currencyCode, otherIncome: otherIncome, firstDay: nil
        )
    }

    /// What `transactions` count in the Total, in `currencyCode`, where `firstDay`, read from the store, is the first
    /// day anything counts: Home's Month graph, which holds only some months.
    init(_ transactions: [Transaction], currencyCode: String, otherIncome: Category, firstDay: CalendarDay?) {
        self.init(
            transactions, selection: .total, currencyCode: currencyCode, otherIncome: otherIncome,
            firstDay: .some(firstDay)
        )
    }

    private init(
        _ transactions: [Transaction], selection: WalletSelection, currencyCode: String, otherIncome: Category,
        firstDay: CalendarDay??
    ) {
        var counted: [CountedAmount] = []
        var sources: [Transaction] = []
        for transaction in transactions {
            guard let amount = transaction.countedAmount(in: selection, otherIncome: otherIncome) else { continue }
            counted.append(amount)
            sources.append(transaction)
        }
        self.selection = selection
        self.currencyCode = currencyCode
        self.counted = counted
        self.transactions = sources
        self.firstDay = firstDay ?? counted.firstDay
    }

    /// The periods of `timeRange` the strip offers: from the one holding ``firstDay`` through the one holding `today`,
    /// or that one alone when nothing counts. Never Future.
    func strip(_ timeRange: TimeRange, today: CalendarDay) -> [Period] {
        timeRange.pastPeriods(from: firstDay, today: today)
    }

    /// The days a Report screen's `period` covers, as its Steps and Daily average count them: the period's days through
    /// today, where All time reaches back to ``firstDay``.
    func days(of period: Period, today: CalendarDay) -> DayRange {
        let days = period.days(today: today)
        return DayRange(first: days.first ?? firstDay ?? today, last: days.last ?? today)
    }

    /// What counts on the days of `period` up to `today`: what the Report adds up. Nothing dated after today is in any
    /// Report period.
    func during(_ period: Period, today: CalendarDay) -> [CountedAmount] {
        let days = period.days(today: today)
        return counted.filter { days.contains($0.day) }
    }

    /// The transactions whose counted amount falls in `days` and `matches`, newest day first, and what they count.
    func transactions(
        on days: DayRange, where matches: (CountedAmount) -> Bool
    ) -> (transactions: [Transaction], totals: PeriodTotals) {
        var listed: [Transaction] = []
        var amounts: [CountedAmount] = []
        for (transaction, amount) in zip(transactions, counted) where days.contains(amount.day) && matches(amount) {
            listed.append(transaction)
            amounts.append(amount)
        }
        return (listed.inListOrder(), PeriodTotals(of: amounts, currencyCode: currencyCode))
    }

    /// The Month graph tab for `side` showing `period` as it stands on `today`, with what `recurring` still has due,
    /// compared with `choice`; or `nil` for a period of no fixed length (All time, a custom range), which has no graph.
    func graph(
        _ side: SpentOrIncome, in period: Period, recurring: [RecurringTransaction], today: CalendarDay,
        comparingWith choice: MonthGraphComparison
    ) -> MonthGraph? {
        guard GraphSpan(period) != nil else { return nil }
        return MonthGraph(
            side, of: counted, countingFrom: firstDay, recurring: recurring, in: period, today: today,
            comparingWith: choice, selection: selection, currencyCode: currencyCode
        )
    }

    /// The Month graph tab for `side` showing `month`, as Home's Month graph draws it.
    func graph(
        _ side: SpentOrIncome, of month: CalendarMonth, recurring: [RecurringTransaction], today: CalendarDay,
        comparingWith choice: MonthGraphComparison = .average
    ) -> MonthGraph {
        MonthGraph(
            side, of: counted, countingFrom: firstDay, recurring: recurring, in: .month(month), today: today,
            comparingWith: choice, selection: selection, currencyCode: currencyCode
        )
    }
}
