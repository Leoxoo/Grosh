import SwiftData

extension TransactionDefaults {
    /// The starting values of a new transfer, dated `today`: from the ``wallet(viewing:in:)`` (the wallet the
    /// Transactions tab is showing, or else the last-used one), to the first other unarchived wallet in the user's
    /// order.
    static func suggestTransfer(on today: CalendarDay, viewing viewed: Wallet? = nil, in context: ModelContext) -> TransferDraft {
        var draft = TransferDraft(day: today)
        draft.from = wallet(viewing: viewed, in: context)
        draft.to = ((try? context.fetch(Wallet.unarchived)) ?? []).first { $0 != draft.from }
        return draft
    }
}
