import Foundation
import SwiftData

/// Money moved between two of the user's own wallets (ADR-0002). It is not a record of its own: it is two
/// ordinary transactions sharing a link, an Outgoing transfer in the source wallet and an Incoming transfer in
/// the destination.
struct Transfer {
    let outgoing: Transaction
    let incoming: Transaction
}

extension Transfer {
    /// Records the draft as its two linked halves, entered now. Saves. Nothing is recorded when the draft breaks
    /// a transfer rule.
    @discardableResult
    static func create(_ draft: TransferDraft, in context: ModelContext) throws -> Transfer {
        try draft.validate()
        let link = UUID()
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)

        func half(_ role: LockedRole, _ cents: Int, in wallet: Wallet?) throws -> Transaction {
            let category = try context.lockedCategory(role)
            let half = Transaction(amount: Money(cents: cents), day: draft.day, wallet: nil, category: nil, note: note)
            context.insert(half)
            half.wallet = wallet
            half.category = category
            half.linkID = link
            return half
        }

        let transfer = Transfer(
            outgoing: try half(.outgoingTransfer, -draft.amount.cents, in: draft.from),
            incoming: try half(.incomingTransfer, draft.amount.cents, in: draft.to)
        )
        try context.save()
        return transfer
    }
}
