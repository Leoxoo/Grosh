/// What sort of Recurring transaction it is, kept apart from its category. The Recurring tab lists them in this order.
nonisolated enum RecurringKind: String, CaseIterable, Sendable {
    case bill, subscription, purchase, regular

    /// Whether a Recurring transaction of this Kind starts each transaction it makes as an estimate, given its "amount
    /// varies" switch. Only a Bill's amount can vary, so the switch means nothing for any other Kind.
    func estimates(amountVaries: Bool) -> Bool {
        self == .bill && amountVaries
    }
}
