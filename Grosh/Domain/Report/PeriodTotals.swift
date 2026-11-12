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

    /// The totals of what `counted` adds up to on each side, in `currencyCode` (``CountedHistory/currencyCode``).
    init(of counted: [CountedAmount], currencyCode: String) {
        var incomeCents = 0
        var spentCents = 0
        for amount in counted {
            switch amount.side {
            case .income: incomeCents += amount.amount.cents
            case .spent: spentCents += amount.amount.cents
            }
        }
        self.init(
            income: Money(cents: incomeCents, currencyCode: currencyCode),
            spent: Money(cents: spentCents, currencyCode: currencyCode)
        )
    }

    /// Income less Spent: what the period came to, positive when more came in than went out.
    var netIncome: Money {
        Money(cents: income.cents - spent.cents, currencyCode: income.currencyCode)
    }

    /// The side's total, as its tab, bar and row show it.
    func total(of side: SpentOrIncome) -> Money {
        switch side {
        case .income: income
        case .spent: spent
        }
    }

    /// How much of the width the side's bar on the Net income card fills, 0 to 1: all of it for the larger side and
    /// in proportion for the other. A side below zero (more refunded than spent) or a period with nothing fills none.
    func barFraction(of side: SpentOrIncome) -> Double {
        let largest = max(income.cents, spent.cents)
        guard largest > 0 else { return 0 }
        return min(max(Double(total(of: side).cents) / Double(largest), 0), 1)
    }
}
