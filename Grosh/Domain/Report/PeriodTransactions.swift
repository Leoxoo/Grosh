/// The transactions a Net income or Trend row lists for its Step: those that count in its days, toward `side` when one is
/// given and toward either side otherwise. They are listed newest day first, and `total` is what they count: the side's
/// amount, or Net income when both sides are listed. An Expense paid back beyond its amount counts the extra under
/// `otherIncome`.
struct PeriodTransactions {
    let transactions: [Transaction]
    let total: Money

    init(
        side: SpentOrIncome?, of transactions: [Transaction], in selection: WalletSelection, days: DayRange,
        otherIncome: Category
    ) {
        var listed: [Transaction] = []
        var incomeCents = 0
        var spentCents = 0
        for transaction in transactions {
            guard let counted = transaction.countedAmount(in: selection, otherIncome: otherIncome),
                  days.contains(counted.day),
                  side == nil || counted.side == side
            else { continue }
            listed.append(transaction)
            switch counted.side {
            case .income: incomeCents += counted.amount.cents
            case .spent: spentCents += counted.amount.cents
            }
        }
        self.transactions = listed.inListOrder()
        switch side {
        case .income: self.total = Money(cents: incomeCents)
        case .spent: self.total = Money(cents: spentCents)
        case nil: self.total = Money(cents: incomeCents - spentCents)
        }
    }
}
