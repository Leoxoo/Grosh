import Foundation
import SwiftData

extension Transaction {
    /// Whether it can be moved into `expense` as a Reimbursement: when nothing blocks it
    /// (``reimbursementMoveInBlocker(into:)``).
    func canBeMovedIntoReimbursement(of expense: Transaction) -> Bool {
        reimbursementMoveInBlocker(into: expense) == nil
    }

    /// Why it can't be moved into `expense` as a Reimbursement, or `nil` when it can: it must be money that came in
    /// under an Income category, outside Recently Deleted, into the Expense's own wallet. A transfer's incoming half, a
    /// balance adjustment, a Loan or Debt and their payments, and what an overpaid Loan brought in can't; money paid
    /// into another wallet is a transfer or income, never a Reimbursement (ADR-0008).
    func reimbursementMoveInBlocker(into expense: Transaction) -> ReimbursementRuleError? {
        guard deletedAt == nil, category?.type == .income, category?.isTransferHalf != true, !isBalanceAdjustment,
              amountCents > 0
        else { return .notADeposit }
        guard let wallet, wallet === expense.wallet else { return .otherWallet }
        return isDebtWriteOff ? .notADeposit : nil
    }

    /// The Reimbursements as the row lists them, earliest first: "+20, +10, +3.50". A whole amount drops its cents.
    func reimbursementSummary(locale: Locale = .current) -> String {
        orderedReimbursements.map { Self.paidBackText($0.amountCents, locale: locale) }.joined(separator: ", ")
    }

    /// An amount paid back as a row lists it: "+20" or "+3.50". A whole amount drops its cents.
    static func paidBackText(_ cents: Int, locale: Locale = .current) -> String {
        "+" + Money.plainNumber(cents: cents, locale: locale)
    }

    /// What a paid-back Expense comes to in a list showing `listed`, as its row shows it after the amount: its net, or
    /// in the Total its net less what was paid back into other wallets (ADR-0010). `nil` when nothing was paid back or
    /// it comes to the amount itself. The stored figures are read first, so a row never paid back reads nothing else.
    func paidBackNet(_ listed: ListedAmount) -> Money? {
        let isInTotal = listed == .netInTotal
        guard reimbursedCents > 0 || (isInTotal && hasPaybacksElsewhere) else { return nil }
        let net = isInTotal ? totalViewNet : self.net
        return net.cents == amountCents ? nil : net
    }

    /// What was paid back on an Expense as its row lists it under the title in a list showing `listed`: its
    /// Reimbursements, "+20, +10, +3", then in a wallet's own list (not the Total) what was paid back into other wallets,
    /// "+20 to Cash" (ADR-0010). Empty when nothing was. The stored figures are read first, so a row without
    /// Reimbursements never reads them.
    func paidBackSummary(_ listed: ListedAmount, locale: Locale = .current) -> String {
        let summary = reimbursedCents > 0 ? reimbursementSummary(locale: locale) : ""
        let elsewhere = listed == .net && hasPaybacksElsewhere ? elsewhereSummary(locale: locale) : ""
        return [summary, elsewhere].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

nonisolated extension ReimbursementDraft {
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
        try deposit.delete(.onlySelected, at: now)
        return reimbursement
    }
}

extension Transaction {
    /// Undoes moving this deposit into an Expense, as it is restored from Recently Deleted: the Reimbursement it became
    /// comes off the Expense, edited since or not, so the money counts once. Doesn't save.
    func takeBackMovedInReimbursements() throws {
        for reimbursement in movedIntoReimbursements ?? [] {
            try reimbursement.removeFromExpense()
        }
    }
}
