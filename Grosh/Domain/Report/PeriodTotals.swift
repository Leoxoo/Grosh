/// What a period's Income and Spent come to on the Report, and their difference, Net income. Each counts as the Month
/// graph counts it (``CountedAmount``), for the wallet selection the Report shows and only for the days of the period
/// up to today (``CountedHistory/during(_:today:)``), so no Report figure reaches into Future.
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

    /// Income less Spent: what the period came to, positive when more came in than went out.
    var netIncome: Money {
        Money(cents: income.cents - spent.cents)
    }

    /// The side's total, as its tab, bar and row show it.
    func total(of side: SpentOrIncome) -> Money {
        switch side {
        case .income: income
        case .spent: spent
        }
    }
}
