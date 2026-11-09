nonisolated extension RecurringKind {
    /// Whether a Recurring transaction of this Kind starts each transaction it makes as an estimate, given its "amount
    /// varies" switch. Only a Bill's amount can vary, so the switch means nothing for any other Kind.
    func estimates(amountVaries: Bool) -> Bool {
        self == .bill && amountVaries
    }
}

extension RecurringTransaction {
    /// Whether each transaction it makes starts Estimated: a Bill whose amount varies.
    var estimatesAmount: Bool { kind.estimates(amountVaries: amountVaries) }
}
