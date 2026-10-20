/// The transactions a Breakdown row of Income or Spent opens: those counting toward `side` under a parent category, its
/// subcategories included, on the days given. They are listed newest day first, and their `total` is what they count,
/// which is the row's amount in the Breakdown. An Expense paid back beyond its amount counts the extra under
/// `otherIncome`.
struct CategoryTransactions {
    let transactions: [Transaction]
    let total: Money

    init(
        parent: Category, side: SpentOrIncome, of transactions: [Transaction], in selection: WalletSelection,
        days: DayRange, otherIncome: Category
    ) {
        var listed: [Transaction] = []
        var cents = 0
        for transaction in transactions {
            guard let counted = transaction.countedAmount(in: selection, otherIncome: otherIncome),
                  counted.side == side,
                  counted.category.parentOrSelf == parent,
                  days.contains(counted.day) else { continue }
            listed.append(transaction)
            cents += counted.amount.cents
        }
        self.transactions = listed.inListOrder()
        self.total = Money(cents: cents)
    }
}
