/// What the Recurring tab lists, grouped by Kind.
enum RecurringListing {
    /// The Recurring transactions of one Kind, in the order the tab lists them.
    struct KindGroup: Identifiable {
        let kind: RecurringKind
        let items: [RecurringTransaction]

        var id: RecurringKind { kind }
    }

    /// The groups of `recurring` in ``RecurringKind``'s order, leaving out any Kind with no Recurring transaction.
    static func groups(of recurring: [RecurringTransaction]) -> [KindGroup] {
        RecurringKind.allCases.compactMap { kind -> KindGroup? in
            let items = recurring.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            return KindGroup(kind: kind, items: items)
        }
    }
}
