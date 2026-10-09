/// The balance at the start and at the end of a period, as the top of the Transactions tab shows them.
///
/// Both are balances, so they count every transaction, excluded from report or not.
struct PeriodSummary: Equatable {
    /// The balance before the period's first day: the previous period's Ending balance.
    var openingBalance: Money
    /// The balance at the end of the period's last day. For Future, the projected balance.
    var endingBalance: Money

    var difference: Money {
        Money(cents: endingBalance.cents - openingBalance.cents, currencyCode: endingBalance.currencyCode)
    }
}

extension PeriodSummary {
    /// The summary of `period` for a set of transactions, such as every transaction of the selected wallet.
    /// `transactions` must reach back before the period, since the Opening balance is built from them.
    init(of transactions: [Transaction], in period: Period, today: CalendarDay) {
        let days = period.days(today: today)
        var opening = 0
        var ending = 0
        for transaction in transactions {
            let day = transaction.day
            if let first = days.first, day < first {
                opening += transaction.amountCents
            }
            if days.last.map({ day <= $0 }) ?? true {
                ending += transaction.amountCents
            }
        }
        self.init(openingBalance: Money(cents: opening), endingBalance: Money(cents: ending))
    }
}
