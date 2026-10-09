import SwiftData

extension TransactionDefaults {
    /// The starting values of a new transfer, dated `today`: from `viewed` (the wallet the Transactions tab is
    /// showing) or else the wallet a new transaction would suggest (the last-used one), to the first other
    /// unarchived wallet in the user's order.
    static func suggestTransfer(on today: CalendarDay, from viewed: Wallet? = nil, in context: ModelContext) -> TransferDraft {
        var draft = TransferDraft(day: today)
        draft.from = viewed ?? suggest(on: today, in: context).wallet
        draft.to = ((try? context.fetch(Wallet.unarchived)) ?? []).first { $0 != draft.from }
        return draft
    }
}
