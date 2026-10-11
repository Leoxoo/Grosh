/// What sort of Recurring transaction it is, kept apart from its category. The Recurring tab lists them in this order.
nonisolated enum RecurringKind: String, CaseIterable, Sendable {
    case bill, subscription, purchase, regular
}
