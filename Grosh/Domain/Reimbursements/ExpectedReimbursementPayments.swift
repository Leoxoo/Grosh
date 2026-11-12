import Foundation
import SwiftData

/// What the Record payment sheet holds for an Expected reimbursement: an amount, the day the money was received, an
/// optional note and the wallet it came into.
nonisolated struct ExpectationPaymentDraft {
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

extension ExpectedReimbursement {
    /// Checks a payment before anything is recorded: something must still be expected, the amount above zero, and the
    /// Expense able to take it in the wallet chosen (``Transaction/checkPayback(into:)``).
    func validate(_ draft: ExpectationPaymentDraft) throws {
        guard isOpen else { throw ExpectedReimbursementRuleError.notOpen }
        guard draft.amount.cents > 0 else { throw ReimbursementRuleError.missingAmount }
        guard let expense else { throw ReimbursementRuleError.notAnExpense }
        try expense.checkPayback(into: draft.wallet)
    }

    /// Records the payment against this expectation. In the Expense's own wallet it is a Reimbursement on the Expense:
    /// its net lands in that wallet on the Expense's own day, as for any Reimbursement. Paid more than expected, the
    /// excess follows the Reimbursement rule and counts as Other Income. An expectation with an amount closes itself
    /// once its payments cover it; an open amount stays open until closed by hand. In another wallet it is a real
    /// transaction there, with the Person in With (``Transaction/recordPaybackElsewhere(_:into:from:for:)``). Saves.
    func recordPayment(_ draft: ExpectationPaymentDraft) throws {
        try validate(draft)
        guard let expense else { throw ReimbursementRuleError.notAnExpense }
        let entry = ReimbursementDraft(amount: draft.amount, day: draft.day, note: draft.note)
        try expense.recordPayback(entry, into: draft.wallet, from: person, for: self)
    }
}

// MARK: Paid back into another wallet

extension Transaction {
    /// Checks money paid back on this Expense before anything is recorded: the amount above zero, and the Expense able
    /// to take it in `wallet` (``checkPayback(into:)``).
    func validatePayback(_ draft: ReimbursementDraft, into wallet: Wallet?) throws {
        try draft.validate()
        try checkPayback(into: wallet)
    }

    /// Someone paid this Expense back `draft`, into `wallet`: into its own wallet (or none chosen) it is a
    /// Reimbursement on the Expense (ADR-0008); into another wallet it is a transaction there, linked to the Expense
    /// (``recordPaybackElsewhere(_:into:from:for:)``, ADR-0010). `person` paid it, against `expectation`, when
    /// someone owed it. Saves.
    func recordPayback(
        _ draft: ReimbursementDraft, into wallet: Wallet?, from person: Person? = nil,
        for expectation: ExpectedReimbursement? = nil
    ) throws {
        if isElsewhere(wallet), let wallet {
            try recordPaybackElsewhere(draft, into: wallet, from: person, for: expectation)
        } else {
            try Reimbursement.add(draft, to: self, for: expectation, in: storeContext())
        }
    }

    /// Whether money received into `wallet` is paid back elsewhere: a transaction in that wallet (ADR-0010) rather than
    /// a Reimbursement on this Expense (ADR-0008).
    func isElsewhere(_ wallet: Wallet?) -> Bool {
        wallet != nil && wallet !== self.wallet
    }

    /// Checks that money received into `wallet` can be recorded against this Expense: it must be an Expense, and money
    /// paid back elsewhere must be in its currency and can't be paid against a part of a Split, whose parts are
    /// independent (ADR-0007).
    func checkPayback(into wallet: Wallet?) throws {
        guard canBeReimbursed else { throw ReimbursementRuleError.notAnExpense }
        guard isElsewhere(wallet), let wallet else { return }
        guard wallet.currencyCode == amount.currencyCode else { throw ExpectedReimbursementRuleError.otherCurrency }
        // Only an Expense on no link, or already on its paybacks' (ADR-0012), takes one.
        guard linkKind == nil || linkKind == .payback else { throw ExpectedReimbursementRuleError.splitPart }
    }

    /// Someone paid this Expense back into `wallet`, another wallet than its own: a transaction in that wallet, dated
    /// the day it was received, filed under the locked Reimbursement category, with `person` in With when there is one,
    /// against `expectation` when someone owed it, and linked to the Expense like the halves of a transfer, so they show
    /// as each other's Related transactions and are deleted together (ADR-0010). It counts in its wallet's balance and
    /// report as money in. Saves.
    @discardableResult
    func recordPaybackElsewhere(
        _ draft: ReimbursementDraft, into wallet: Wallet, from person: Person? = nil,
        for expectation: ExpectedReimbursement? = nil
    ) throws -> Transaction {
        try draft.validate()
        try checkPayback(into: wallet)
        let context = try storeContext()
        let category = try context.lockedCategory(.reimbursement)
        hasPaybacksElsewhere = true
        let payback = Transaction.insert(
            cents: draft.amount.cents, on: draft.day, wallet: wallet, category: category,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines), in: context
        )
        payback.setPeople(person.map { [$0] } ?? [])
        payback.join(self, as: .payback)
        payback.paidBackExpense = self
        payback.paidExpectation = expectation
        try context.save()
        return payback
    }

    /// The money paid back into other wallets against this Expense, outside Recently Deleted, the earliest day first.
    /// Only an Expense with ``hasPaybacksElsewhere`` has any, so the rest never walk a relationship.
    var paybacksElsewhere: [Transaction] {
        guard hasPaybacksElsewhere else { return [] }
        return (paybacks ?? [])
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
    /// The Total list and report read this for every transaction, so it asks first what its stored link kind says,
    /// before reading any relationship: only a transaction on a payback's link can be one (ADR-0012).
    var isHiddenInTotal: Bool {
        guard linkKind == .payback, isFiledAsPayback, let expense = paidBackExpense else { return false }
        return !expense.isInRecentlyDeleted && expense.wallet?.countsInTotal == true
    }

    /// Whether it is filed under the locked Reimbursement category: money paid back into another wallet than its
    /// Expense's (ADR-0010).
    var isFiledAsPayback: Bool { category?.lockedRole == .reimbursement }

    /// Called as `removed` leave the store for good: an Expense none of whose paybacks is left, not even in Recently
    /// Deleted, is no longer paid back elsewhere. It leaves the link it shared with them, so it can be split and change
    /// wallet again. Doesn't save.
    func forgetPaybacks(removedForGood removed: Set<PersistentIdentifier>) {
        guard hasPaybacksElsewhere,
              (paybacks ?? []).allSatisfy({ removed.contains($0.persistentModelID) })
        else { return }
        hasPaybacksElsewhere = false
        if linkKind == .payback {
            leaveLink()
        }
    }

    /// What was paid back into other wallets, as the Expense's own wallet's row notes it: "+20 to Cash, +5 to Bank".
    func elsewhereSummary(locale: Locale = .current) -> String {
        paybacksElsewhere.map { payback in
            let amount = Self.paidBackText(payback.amountCents, locale: locale)
            let wallet = payback.wallet?.name ?? ""
            return String(localized: Strings.OwesMe.paidTo(amount, wallet))
        }
        .joined(separator: ", ")
    }
}
