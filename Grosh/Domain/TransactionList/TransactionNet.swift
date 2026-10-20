extension Sequence where Element == Transaction {
    /// What the transactions add to or take from the balance together: every one counts, excluded from report or
    /// not, each as its net (``Transaction/netCents``). A day's or a category's total in the list, or what a search or
    /// filter matches. A Card's total is ``charged`` instead.
    var net: Money {
        Money(cents: reduce(0) { $0 + $1.netCents })
    }

    /// What the Card was charged for the transactions together: their original amounts, Reimbursements not counted, as
    /// on the Card's statement. A Card's statement total, and the Card filter's.
    var charged: Money {
        Money(cents: reduce(0) { $0 + $1.amountCents })
    }
}
