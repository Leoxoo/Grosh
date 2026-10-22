import Foundation
import SwiftData

extension Transaction {
    /// Whether it can be moved into `expense` as a Reimbursement: when nothing blocks it
    /// (``reimbursementMoveInBlocker(into:loanOrDebtLinks:)``).
    func canBeMovedIntoReimbursement(of expense: Transaction, loanOrDebtLinks: Set<UUID>? = nil) -> Bool {
        reimbursementMoveInBlocker(into: expense, loanOrDebtLinks: loanOrDebtLinks) == nil
    }

    /// Why it can't be moved into `expense` as a Reimbursement, or `nil` when it can: it must be money that came in
    /// under an Income category, outside Recently Deleted, into the Expense's own wallet. A transfer's incoming half, a
    /// balance adjustment, a Loan or Debt and their payments, and what an overpaid Loan brought in can't; money paid
    /// into another wallet is a transfer or income, never a Reimbursement (ADR 0008). A screen checking many reads
    /// `loanOrDebtLinks` once (``Transaction/loanOrDebtLinks(in:)``); without them, a linked Income reads the store.
    func reimbursementMoveInBlocker(
        into expense: Transaction, loanOrDebtLinks: Set<UUID>? = nil
    ) -> ReimbursementRuleError? {
        guard deletedAt == nil, category?.type == .income, category?.isTransferHalf != true, !isBalanceAdjustment,
              amountCents > 0
        else { return .notADeposit }
        guard let wallet, wallet === expense.wallet else { return .otherWallet }
        let isWriteOff = loanOrDebtLinks.map { isDebtWriteOff(loanOrDebtLinks: $0) } ?? isDebtWriteOff
        return isWriteOff ? .notADeposit : nil
    }

    /// The Reimbursements as the row lists them, earliest first: "+20, +10, +3.50". A whole amount drops its cents.
    func reimbursementSummary(locale: Locale = .current) -> String {
        orderedReimbursements.map { Self.paidBackText($0.amountCents, locale: locale) }.joined(separator: ", ")
    }

    /// An amount paid back as a row lists it: "+20" or "+3.50". A whole amount drops its cents.
    static func paidBackText(_ cents: Int, locale: Locale = .current) -> String {
        "+" + Money(cents: cents).plainNumber(locale: locale)
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
        if let blocker = deposit.reimbursementMoveInBlocker(into: expense) { throw blocker }
        let reimbursement = try add(ReimbursementDraft(movingIn: deposit), to: expense, in: context)
        reimbursement.movedFrom = deposit
        try deposit.delete(.onlySelected, in: context, at: now)
        return reimbursement
    }
}

extension Transaction {
    /// Undoes moving this deposit into an Expense, as it is restored from Recently Deleted: the Reimbursement it became
    /// comes off the Expense, edited since or not, so the money counts once. Doesn't save.
    func takeBackMovedInReimbursements() {
        for reimbursement in movedIntoReimbursements ?? [] {
            reimbursement.removeFromExpense()
        }
    }
}
