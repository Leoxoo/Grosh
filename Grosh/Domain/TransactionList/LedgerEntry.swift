/// What balances, Opening and Ending balances and the period strip read of a transaction: its wallet, its day and
/// what it adds to or takes from the wallet.
protocol DatedAmount {
    var wallet: Wallet? { get }
    /// The ``CalendarDay`` as `yyyymmdd`.
    var dayRaw: Int { get }
    /// Signed effect on the wallet in cents.
    var amountCents: Int { get }
}

extension Transaction: DatedAmount {}

/// A transaction with its ``DatedAmount`` read once, as ``NotDeletedTransactions`` keeps every transaction outside
/// Recently Deleted. The screens that add balances up read these rather than the transactions: a transaction's values
/// are slow to read while a screen draws, and a balance reads every transaction. Each is read again from its transaction
/// whenever a save changes it.
struct LedgerEntry: DatedAmount {
    let transaction: Transaction
    let wallet: Wallet?
    let dayRaw: Int
    let amountCents: Int

    init(_ transaction: Transaction) {
        self.transaction = transaction
        wallet = transaction.wallet
        dayRaw = transaction.dayRaw
        amountCents = transaction.amountCents
    }

    /// Whether `other` holds the same wallet, day and amount.
    func hasSameFigures(as other: LedgerEntry) -> Bool {
        wallet === other.wallet && dayRaw == other.dayRaw && amountCents == other.amountCents
    }
}

extension Sequence where Element: DatedAmount {
    /// The earliest day any of them is dated, or `nil` when there are none: where a period strip of them starts.
    var firstDay: CalendarDay? {
        map(\.dayRaw).min().map(CalendarDay.init(rawValue:))
    }
}
