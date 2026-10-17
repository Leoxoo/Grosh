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

    /// The totals of what `counted` adds up to on each side.
    init(of counted: [CountedAmount]) {
        var incomeCents = 0
        var spentCents = 0
        for amount in counted {
            switch amount.side {
            case .income: incomeCents += amount.amount.cents
            case .spent: spentCents += amount.amount.cents
            }
        }
        self.init(income: Money(cents: incomeCents), spent: Money(cents: spentCents))
    }

    /// The totals of `period` for the transactions of `selection`, as of `today`.
    init(of transactions: [Transaction], in selection: WalletSelection, period: Period, today: CalendarDay) {
        self.init(of: transactions.counted(in: selection, during: period, today: today))
    }

    /// Income less Spent: what the period came to, positive when more came in than went out.
    var netIncome: Money {
        Money(cents: income.cents - spent.cents)
    }
}

extension Sequence where Element == Transaction {
    /// What these transactions count toward Spent or Income in `selection`, on the days of `period` up to `today`: what
    /// the Report adds up. Nothing dated after today is in any Report period.
    func counted(in selection: WalletSelection, during period: Period, today: CalendarDay) -> [CountedAmount] {
        let days = period.days(today: today)
        return compactMap { $0.countedAmount(in: selection) }.filter { days.contains($0.day) }
    }
}
