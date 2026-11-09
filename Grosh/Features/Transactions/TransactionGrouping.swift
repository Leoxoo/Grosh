/// How the transaction list groups a period's transactions, chosen in the "…" menu: by day (the default), or by
/// category with each category's total.
enum TransactionGrouping: Hashable {
    case day
    case category
}
