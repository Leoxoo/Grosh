extension Transaction {
    /// Whether the transaction counts in income and spending statistics (the report). One excluded from report
    /// doesn't, and neither half of a transfer does, whatever its flag says: moving money between the user's own
    /// wallets is never income or spending. Every transaction still counts in its wallet's balance.
    var countsInReport: Bool {
        !isExcludedFromReport && category?.isTransferHalf != true
    }
}
