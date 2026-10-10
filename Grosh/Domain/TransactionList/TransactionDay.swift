/// One day of the transaction list: the day's transactions and their net total.
struct TransactionDay: Identifiable {
    let day: CalendarDay
    /// The most recently entered first.
    let transactions: [Transaction]

    var id: CalendarDay { day }

    /// What the day added to or took from the balance: every transaction counts, excluded from report or not,
    /// so the days of a period add up to its difference.
    var net: Money { transactions.net }
}

extension TransactionDay {
    /// `transactions` grouped by day: only days that have transactions, newest day first, and within a day the
    /// most recently entered transaction on top.
    static func days(of transactions: [Transaction]) -> [TransactionDay] {
        var days: [TransactionDay] = []
        var current: [Transaction] = []
        for transaction in transactions.inListOrder() {
            if let last = current.last, last.dayRaw != transaction.dayRaw {
                days.append(TransactionDay(day: last.day, transactions: current))
                current = []
            }
            current.append(transaction)
        }
        if let last = current.last {
            days.append(TransactionDay(day: last.day, transactions: current))
        }
        return days
    }
}
