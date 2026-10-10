import Foundation
import SwiftData

/// What the editor of one transfer half holds: its amount (entered positive; the half sets the sign), date and
/// note. Its wallet and category stay as the transfer recorded them.
struct TransferHalfDraft {
    var amount: Money
    var day: CalendarDay
    var note: String

    /// The half as it is, to edit.
    init(editing half: Transaction) {
        amount = Money(cents: abs(half.amountCents), currencyCode: half.amount.currencyCode)
        day = half.day
        note = half.note
    }

    /// Checks the draft against the transfer rules before anything is saved.
    func validate() throws {
        guard amount.cents > 0 else { throw TransferRuleError.missingAmount }
    }

    /// Whether the amount is filled in, so Save can be enabled.
    var canSave: Bool { (try? validate()) != nil }
}

/// Which halves of a transfer an edit to one of them changes.
nonisolated enum TransferUpdateScope: Hashable, Sendable {
    /// This half, and the other half takes over its new amount or date.
    case bothHalves
    /// Just this half, so the two can differ, as when a fee was taken.
    case onlyThisOne
}

extension Transaction {
    /// Whether saving `draft` over this transfer half asks to update the other half too (Update Both / Only This
    /// One): only for a new amount or date. A new note, or a half whose other half was deleted on its own, simply
    /// changes this one.
    func offersToUpdateOtherHalf(with draft: TransferHalfDraft, in context: ModelContext) throws -> Bool {
        let changesBoth = draft.amount.cents != abs(amountCents) || draft.day != day
        return try changesBoth && otherHalf(in: context) != nil
    }

    /// Saves an edited transfer half, and with ``TransferUpdateScope/bothHalves`` carries a new amount or date over
    /// to the other half: a date-only change keeps a fee the halves already differ by. The note is this half's
    /// own. Saves. Nothing changes when the draft breaks a transfer rule.
    func update(with draft: TransferHalfDraft, scope: TransferUpdateScope, in context: ModelContext) throws {
        guard editFlow == .transferHalf else { throw TransferRuleError.notATransferHalf }
        try draft.validate()
        let changesAmount = draft.amount.cents != abs(amountCents)
        let changesDay = draft.day != day
        amountCents = draft.amount.cents * (category?.sign ?? 1)
        day = draft.day
        note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == .bothHalves, let other = try otherHalf(in: context) {
            if changesAmount { other.amountCents = -amountCents }
            if changesDay { other.day = day }
        }
        try context.save()
    }

    /// The other half of the transfer this transaction is half of, or `nil` once it was deleted on its own.
    func otherHalf(in context: ModelContext) throws -> Transaction? {
        try related(in: context).first { $0.category?.isTransferHalf == true }
    }

    /// Where the money of the transfer this transaction is half of left and where it went, seen from either half:
    /// the Outgoing transfer's wallet and the Incoming transfer's. The other half's is `nil` once that half was
    /// deleted on its own.
    func transferWallets(in context: ModelContext) throws -> (from: Wallet?, to: Wallet?) {
        let otherWallet = try otherHalf(in: context)?.wallet
        return category?.lockedRole == .outgoingTransfer ? (wallet, otherWallet) : (otherWallet, wallet)
    }
}
