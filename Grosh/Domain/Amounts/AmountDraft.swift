import Foundation

/// A draft whose amount is typed on the Keypad: what a sheet holds before it is saved, such as a transaction, a
/// transfer or a payment.
nonisolated protocol AmountDraft {
    var amount: Money { get set }
}

nonisolated extension AmountDraft {
    /// The draft with the amount `entry` comes to, in `currencyCode`: what the sheet checks and saves. An empty entry,
    /// or one showing an error such as a division by zero, comes to zero, which no draft that needs an amount saves.
    func withAmount(of entry: AmountEntry, in currencyCode: String) -> Self {
        var result = self
        result.amount = Money(cents: entry.cents ?? 0, currencyCode: currencyCode)
        return result
    }
}

extension TransactionDraft: AmountDraft {}
extension TransferDraft: AmountDraft {}
extension TransferHalfDraft: AmountDraft {}
extension RecurringDraft: AmountDraft {}
extension ReimbursementDraft: AmountDraft {}
extension ExpectationPaymentDraft: AmountDraft {}
extension DebtPaymentDraft: AmountDraft {}
extension StartingBalanceDraft: AmountDraft {}
extension SplitPart: AmountDraft {}
