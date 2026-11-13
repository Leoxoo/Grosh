import Foundation
import SwiftData

/// What the Starting balance editor holds: unlike the Add sheet, the amount is signed as entered, since a
/// wallet such as a credit line can start below zero.
nonisolated struct StartingBalanceDraft {
    /// The money the wallet held when it was added, typed with a leading minus when it started in debt.
    var entry: AmountEntry
    let currencyCode: String
    var day: CalendarDay
    var note: String

    init(editing transaction: Transaction) {
        entry = AmountEntry(cents: transaction.amountCents, kind: .balance)
        currencyCode = transaction.amount.currencyCode
        day = transaction.day
        note = transaction.note
    }

    /// Checks that it can be saved: whenever the Keypad shows an amount, zero included, and not an error such as a
    /// division by zero.
    func validate() throws {
        guard entry.cents != nil else { throw TransactionRuleError.missingAmount }
    }
}

extension Transaction {
    /// Saves an edited Starting balance. It stays under the Starting balance category and excluded from report.
    func update(with draft: StartingBalanceDraft) throws {
        guard editFlow == .startingBalance else { throw TransactionRuleError.notAStartingBalance }
        try draft.validate()
        changeCounted {
            $0.amountCents = draft.amount.cents
            $0.day = draft.day
        }
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        try saveToStore()
    }
}
