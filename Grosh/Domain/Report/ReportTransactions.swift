/// The transactions a Report list shows, newest day first, and `total`, what they count. A Net income or Trend row opens
/// those of its Step; a Breakdown row those of its parent category. Each is listed by what it counts
/// (``CountedHistory``), so an Expense paid back beyond its amount is listed on the Income side, under Other Income.
struct ReportTransactions {
    let transactions: [Transaction]
    let total: Money

    /// Those that count in a Step's `days`: toward `side`, its total the side's amount, or toward either side when
    /// `side` is `nil`, its total Net income.
    init(step side: SpentOrIncome?, on days: DayRange, in history: CountedHistory) {
        let listed = history.transactions(on: days) { side == nil || $0.side == side }
        transactions = listed.transactions
        total = side.map { listed.totals.total(of: $0) } ?? listed.totals.netIncome
    }

    /// Those counting toward `side` under `parent`, its subcategories included, on `days`. Their total is the row's
    /// amount in the Breakdown.
    init(category parent: Category, side: SpentOrIncome, on days: DayRange, in history: CountedHistory) {
        let listed = history.transactions(on: days) { $0.side == side && $0.category.parentOrSelf == parent }
        transactions = listed.transactions
        total = listed.totals.total(of: side)
    }
}
