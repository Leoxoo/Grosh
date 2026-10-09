import Foundation

/// What the Starting balance editor holds: unlike the Add sheet, the amount is signed as entered, since a
/// wallet such as a credit line can start below zero.
struct StartingBalanceDraft {
    /// The money the wallet held when it was added: negative when it started in debt.
    var amount: Money
    var day: CalendarDay
    var note: String

    /// The Starting balance as it is, to edit.
    init(editing transaction: Transaction) {
        amount = transaction.amount
        day = transaction.day
        note = transaction.note
    }
}

extension Transaction {
    /// Saves an edited Starting balance. It stays under the Starting balance category and excluded from report.
    func update(with draft: StartingBalanceDraft) throws {
        guard editFlow == .startingBalance else { throw TransactionRuleError.notAStartingBalance }
        amountCents = draft.amount.cents
        day = draft.day
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
