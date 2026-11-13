import Foundation

/// A draft whose amount is typed on the Keypad: what a sheet holds before it is saved, such as a transaction, a
/// transfer or a payment. The draft holds the amount as the Keypad shows it, starting from its own rule, and the sheet's
/// Keypad types straight into it, so what the sheet checks and saves is always the draft itself.
nonisolated protocol AmountDraft {
    /// The amount as typed on the Keypad.
    var entry: AmountEntry { get set }
    /// The currency the amount is in: the wallet's, or the transaction's it pays back or pays toward.
    var currencyCode: String { get }
}

nonisolated extension AmountDraft {
    /// What ``entry`` comes to, in ``currencyCode``. An empty entry, or one showing an error such as a division by zero,
    /// comes to zero, which no draft that needs an amount saves.
    var amount: Money { Money(cents: entry.cents ?? 0, currencyCode: currencyCode) }
}

nonisolated extension TransactionDraft: AmountDraft {}
nonisolated extension TransferDraft: AmountDraft {}
nonisolated extension TransferHalfDraft: AmountDraft {}
nonisolated extension RecurringDraft: AmountDraft {}
nonisolated extension ReimbursementDraft: AmountDraft {}
nonisolated extension ExpectationPaymentDraft: AmountDraft {}
extension DebtPaymentDraft: AmountDraft {}
nonisolated extension StartingBalanceDraft: AmountDraft {}
nonisolated extension SplitPart: AmountDraft {}
