import Foundation
import SwiftData

/// What the Record payment sheet holds for an Expected reimbursement: an amount, the day the money was received, an
/// optional note and the wallet it came into.
struct ExpectationPaymentDraft {
    /// Entered positive. Starts at what is outstanding, so paying in full is one tap; blank (zero) for an open amount.
    var amount: Money
    var day: CalendarDay
    var note = ""
    /// The wallet the money came into. Starts at the Expense's own wallet, which keeps it a Reimbursement on the Expense
    /// (ADR-0008); another wallet makes it a transaction there (ADR-0010).
    var wallet: Wallet?

    /// A payment toward `expectation`, received `day`.
    init(paying expectation: ExpectedReimbursement, on day: CalendarDay) {
        amount = expectation.outstanding ?? Money(cents: 0, currencyCode: expectation.currencyCode)
        self.day = day
        wallet = expectation.expense?.wallet
    }
}

/// What Record payment made.
enum RecordedPayment {
    /// A Reimbursement on the Expense, netted into its own wallet on its own day.
    case onExpense(Reimbursement)
    /// A transaction in another wallet, dated the day received, linked to the Expense (ADR-0010).
    case inOtherWallet(Transaction)
}

extension ExpectedReimbursement {
    /// Checks a payment before anything is recorded: something must still be expected, the amount above zero, the
    /// Expense still an Expense that can be paid back, and the wallet in the Expense's currency.
    func validate(_ draft: ExpectationPaymentDraft) throws {
        guard isOpen else { throw ExpectedReimbursementRuleError.notOpen }
        guard draft.amount.cents > 0 else { throw ReimbursementRuleError.missingAmount }
        guard let expense, expense.canBeReimbursed else { throw ReimbursementRuleError.notAnExpense }
        if let wallet = draft.wallet, wallet.currencyCode != currencyCode {
            throw ExpectedReimbursementRuleError.otherCurrency
        }
    }

    /// Whether money received into `wallet` is paid back elsewhere: a transaction in that wallet (ADR-0010) rather than
    /// a Reimbursement on the Expense (ADR-0008).
    func isElsewhere(_ wallet: Wallet?) -> Bool {
        wallet != nil && wallet !== expense?.wallet
    }

    /// Records the payment against this expectation. In the Expense's own wallet it is a Reimbursement on the Expense:
    /// its net lands in that wallet on the Expense's own day, as for any Reimbursement. Paid more than expected, the
    /// excess follows the Reimbursement rule and counts as Other Income. An expectation with an amount closes itself
    /// once its payments cover it; an open amount stays open until closed by hand. In another wallet it is a real
    /// transaction there (``recordPaybackElsewhere(_:in:)``). Saves.
    @discardableResult
    func recordPayment(_ draft: ExpectationPaymentDraft, in context: ModelContext) throws -> RecordedPayment {
        try validate(draft)
        guard let expense else { throw ReimbursementRuleError.notAnExpense }
        guard isElsewhere(draft.wallet), let wallet = draft.wallet else {
            let entry = ReimbursementDraft(amount: draft.amount, day: draft.day, note: draft.note)
            return .onExpense(try Reimbursement.add(entry, to: expense, for: self, in: context))
        }
        return .inOtherWallet(try recordPaybackElsewhere(draft, in: wallet, of: expense, context: context))
    }

    /// Money Alex paid back into a wallet other than the Expense's: a transaction in that wallet, dated the day it was
    /// received, filed under the locked Reimbursement category, with the Person in With, and linked to the Expense like
    /// the halves of a transfer, so they show as each other's Related transactions and are deleted together
    /// (ADR-0010). It counts in its wallet's balance and report as money in. Saves.
    private func recordPaybackElsewhere(
        _ draft: ExpectationPaymentDraft, in wallet: Wallet, of expense: Transaction, context: ModelContext
    ) throws -> Transaction {
        // The parts of a Split are independent (ADR-0007); a link shared with them would make the payback one too.
        guard expense.linkID == nil || expense.hasPaybacksElsewhere else { throw ExpectedReimbursementRuleError.splitPart }
        let category = try context.lockedCategory(.reimbursement)
        let link = expense.linkID ?? UUID()
        expense.linkID = link
        expense.hasPaybacksElsewhere = true
        let payback = Transaction(amount: draft.amount, day: draft.day, wallet: nil, category: nil)
        context.insert(payback)
        payback.wallet = wallet
        payback.category = category
        payback.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        payback.setPeople(person.map { [$0] } ?? [])
        payback.linkID = link
        payback.paidExpectation = self
        try context.save()
        return payback
    }
}

// MARK: Paid back into another wallet

extension Transaction {
    /// The money paid back into other wallets against this Expense, outside Recently Deleted, the earliest day first.
    /// Only an Expense with ``hasPaybacksElsewhere`` has any, so the rest never walk a relationship.
    var paybacksElsewhere: [Transaction] {
        guard hasPaybacksElsewhere else { return [] }
        return (expectations ?? [])
            .flatMap { $0.paybacks ?? [] }
            .filter { !$0.isInRecentlyDeleted }
            .sorted { ($0.dayRaw, $0.createdAt) < ($1.dayRaw, $1.createdAt) }
    }

    /// What this Expense adds to or takes from the Total: its net (``netCents``) plus what was paid back into the wallets
    /// counted in the Total. A payback into a wallet left out of the Total is not in the Total, so the Expense keeps
    /// that part. The Total list, the Total report and the Month graph read this; its own wallet's list and report read
    /// ``netCents``, the full amount less what came into that wallet (ADR-0010).
    ///
    /// A balance reads ``netCents``, never this: the payback is a transaction in its own wallet and counts there.
    var totalViewNetCents: Int {
        guard hasPaybacksElsewhere else { return netCents }
        return netCents + paybacksElsewhere.filter { $0.wallet?.countsInTotal == true }.reduce(0) { $0 + $1.amountCents }
    }

    /// ``totalViewNetCents`` as money in its wallet's currency.
    var totalViewNet: Money { Money(cents: totalViewNetCents, currencyCode: amount.currencyCode) }

    /// Whether this is a payback the Total list and report leave out, because its Expense, counted in the Total, shows
    /// it in its net (``totalViewNetCents``). A payback whose Expense is outside the Total (or in Recently Deleted)
    /// stays in the Total as the money in it is. Its own wallet's list and report show it.
    ///
    /// The Total list and report read this for every transaction, so it asks first whether it pays an expectation at
    /// all: that is `nil` on all but paybacks, and reading it reads no other record.
    var isHiddenInTotal: Bool {
        guard let expectation = paidExpectation, category?.lockedRole == .reimbursement,
              let expense = expectation.expense
        else { return false }
        return !expense.isInRecentlyDeleted && expense.wallet?.countsInTotal == true
    }

    /// What was paid back into other wallets, as the Expense's own wallet's row notes it: "+20 to Cash, +5 to Bank".
    func elsewhereSummary(locale: Locale = .current) -> String {
        paybacksElsewhere.map { payback in
            let amount = Self.paidBackText(payback.amountCents, locale: locale)
            let wallet = payback.wallet?.name ?? ""
            return String(localized: "\(amount) to \(wallet)")
        }
        .joined(separator: ", ")
    }
}
