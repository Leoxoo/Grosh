import Foundation
import SwiftData

extension Transaction {
    /// Whether it can be moved into an Expense as a Reimbursement: money that came in under an Income category, outside
    /// Recently Deleted. A transfer's incoming half, a balance adjustment, a Loan or Debt and their payments can't.
    var canBeMovedIntoReimbursement: Bool {
        deletedAt == nil && category?.type == .income && category?.isTransferHalf != true && !isBalanceAdjustment
            && amountCents > 0
    }

    /// The Reimbursements as the row lists them, earliest first: "+20, +10, +3.50". A whole amount drops its cents.
    func reimbursementSummary(locale: Locale = .current) -> String {
        orderedReimbursements.map { entry in
            let fractionLength = entry.amountCents % 100 == 0 ? 0 : 2
            let amount = Decimal(entry.amountCents) / 100
            return "+" + amount.formatted(.number.precision(.fractionLength(fractionLength)).locale(locale))
        }
        .joined(separator: ", ")
    }
}

extension ReimbursementDraft {
    /// The entry that moving `deposit` in makes: its amount, its day and its note.
    init(movingIn deposit: Transaction) {
        self.init(amount: deposit.amount, day: deposit.day, note: deposit.note)
    }
}

extension Reimbursement {
    /// Moves an existing deposit into `expense`: its amount, day and note become a Reimbursement of the Expense, and the
    /// deposit goes to Recently Deleted, so it can be restored. Nothing changes when either can't take part. Saves.
    @discardableResult
    static func moveIn(
        _ deposit: Transaction, to expense: Transaction, in context: ModelContext, at now: Date = .now
    ) throws -> Reimbursement {
        guard deposit.canBeMovedIntoReimbursement else { throw ReimbursementRuleError.notADeposit }
        let reimbursement = try add(ReimbursementDraft(movingIn: deposit), to: expense, in: context)
        try deposit.delete(.onlySelected, in: context, at: now)
        return reimbursement
    }
}
