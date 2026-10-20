/// One day of the transaction list: the day's transactions and their net total, and in Future the day's Scheduled rows.
struct TransactionDay: Identifiable {
    let day: CalendarDay
    /// The most recently entered first.
    let transactions: [Transaction]
    /// The Scheduled rows dated this day, listed after its transactions. They count in no total.
    var scheduled: [ScheduledOccurrence] = []

    var id: CalendarDay { day }

    /// What the day added to or took from the balance: every transaction counts, excluded from report or not,
    /// so the days of a period add up to its difference. Scheduled rows aren't transactions and don't count.
    var net: Money { transactions.net }

    /// What the day's transactions come to as `listed`: their ``net``, or on a Card's statement what the Card was
    /// charged.
    func total(_ listed: ListedAmount) -> Money { transactions.total(listed) }
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

    /// `transactions` and the Scheduled rows in `scheduled` grouped by day: every day that has either, newest day
    /// first. A day with only Scheduled rows has no transactions, so no net total.
    static func days(of transactions: [Transaction], scheduled: [ScheduledOccurrence]) -> [TransactionDay] {
        let scheduledByDay = Dictionary(grouping: scheduled, by: \.day)
        let withTransactions = days(of: transactions).map { existing in
            TransactionDay(
                day: existing.day, transactions: existing.transactions, scheduled: scheduledByDay[existing.day] ?? []
            )
        }
        let transactionDays = Set(withTransactions.map(\.day))
        let scheduledOnly = scheduledByDay.keys
            .filter { !transactionDays.contains($0) }
            .map { TransactionDay(day: $0, transactions: [], scheduled: scheduledByDay[$0] ?? []) }
        return (withTransactions + scheduledOnly).sorted { $0.day > $1.day }
    }
}
