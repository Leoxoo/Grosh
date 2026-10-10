extension Sequence where Element == Transaction {
    /// What the transactions add to or take from the balance together: every one counts, excluded from report or
    /// not. A day's or a category's total in the list, or what a search or filter matches (with a Card filter on,
    /// that Card's total).
    var net: Money {
        Money(cents: reduce(0) { $0 + $1.amountCents })
    }
}
