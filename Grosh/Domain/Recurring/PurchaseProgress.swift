import Foundation

/// How much of a Purchase has been paid: what its attached transactions add up to, against its total price when it has one.
nonisolated struct PurchaseProgress: Equatable, Sendable {
    /// What the attached transactions add up to, each counted at its size whichever way it moved the wallet.
    let paid: Money
    /// The total price, or `nil` when the Purchase has none.
    let total: Money?

    /// "$400.00 of $1,200.00 paid", or "$400.00 paid" without a total.
    var summary: String {
        guard let total else {
            return String(localized: Strings.Recurring.paid(paid.formatted()))
        }
        return String(localized: Strings.Recurring.paidOfTotal(paid.formatted(), total.formatted()))
    }
}

extension RecurringTransaction {
    /// The progress a Purchase shows. Attached transactions count as paid, whether made earlier or by the schedule, and
    /// progress never changes the schedule. `nil` for every other Kind.
    var purchaseProgress: PurchaseProgress? {
        guard kind == .purchase else { return nil }
        let paidCents = attachedTransactions.reduce(0) { $0 + abs($1.amountCents) }
        return PurchaseProgress(
            paid: Money(cents: paidCents, currencyCode: currencyCode),
            total: totalCents.map { Money(cents: $0, currencyCode: currencyCode) }
        )
    }
}
