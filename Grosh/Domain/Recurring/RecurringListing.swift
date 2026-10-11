/// What the Recurring tab lists, grouped by Kind: every Recurring transaction, or those paid from one wallet.
enum RecurringListing {
    /// The Recurring transactions of one Kind, in the order the tab lists them.
    struct KindGroup: Identifiable {
        let kind: RecurringKind
        let items: [RecurringTransaction]

        var id: RecurringKind { kind }
    }

    /// The groups of the Recurring transactions paid from `wallet`, or from every wallet when it is `nil`, in
    /// ``RecurringKind``'s order. Kinds with none are left out.
    static func groups(of recurring: [RecurringTransaction], wallet: Wallet? = nil) -> [KindGroup] {
        let shown = recurring.filter { wallet == nil || $0.wallet == wallet }
        return RecurringKind.allCases.compactMap { kind -> KindGroup? in
            let items = shown.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            return KindGroup(kind: kind, items: items)
        }
    }
}
