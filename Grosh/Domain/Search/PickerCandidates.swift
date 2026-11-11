/// What a transaction picker (Link existing, moving a deposit in as a Reimbursement) picks from: its transactions in
/// list order, and whether they come from more than one wallet. Worked out once when the picker opens, so each
/// keystroke of its search only narrows them (``TransactionListing/picking(_:filter:)``) rather than sorting them all
/// again.
nonisolated struct PickerCandidates {
    /// Newest day first and, within a day, the most recently entered first.
    let transactions: [Transaction]
    /// Whether they come from more than one wallet, so a row needs its wallet's icon to tell them apart.
    let spanWallets: Bool

    init(_ transactions: [Transaction]) {
        self.transactions = transactions.inListOrder()
        let first = transactions.first?.wallet
        spanWallets = transactions.contains { $0.wallet !== first }
    }
}
