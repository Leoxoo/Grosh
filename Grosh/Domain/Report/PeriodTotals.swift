/// What a period's Income and Spent come to on the Report, and their difference, Net income. Each counts as the Month
/// graph counts it (``CountedAmount``), for the wallet selection the Report shows and only for the days of the period
/// up to today, so no Report figure reaches into Future.
struct PeriodTotals: Equatable {
    let income: Money
    let spent: Money

    init(income: Money, spent: Money) {
        self.income = income
        self.spent = spent
    }

    /// The totals of `period` for the transactions of `selection`, as of `today`.
    init(of transactions: [Transaction], in selection: WalletSelection, period: Period, today: CalendarDay) {
        let days = period.days(today: today)
        var incomeCents = 0
        var spentCents = 0
        for counted in transactions.compactMap({ $0.countedAmount(in: selection) }) where days.contains(counted.day) {
            switch counted.side {
            case .income: incomeCents += counted.amount.cents
            case .spent: spentCents += counted.amount.cents
            }
        }
        self.init(income: Money(cents: incomeCents), spent: Money(cents: spentCents))
    }

    /// Income less Spent: what the period came to, positive when more came in than went out.
    var netIncome: Money {
        Money(cents: income.cents - spent.cents)
    }
}
