import Foundation
import SwiftData

/// "Suggest defaults": the one place the Add Transaction sheet's starting values come from. The sheet makes no
/// default-value decisions of its own.
///
/// v1 suggests the last-used wallet. A future on-device model that predicts the category and Card from the
/// amount plugs in here, so the sheet doesn't change.
enum TransactionDefaults {
    /// The starting values of a new transaction: an Expense dated `today`, in the last-used wallet, with
    /// nothing else filled in.
    static func suggest(on today: CalendarDay, in context: ModelContext) -> TransactionDraft {
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = lastUsedWallet(in: context)
        return draft
    }

    /// The wallet an action started from a screen begins in: `viewed`, the wallet that screen shows, or else the
    /// wallet a new transaction would suggest (the last-used one).
    static func wallet(viewing viewed: Wallet?, in context: ModelContext) -> Wallet? {
        viewed ?? lastUsedWallet(in: context)
    }

    /// Whether a transaction of `type` starts excluded from report. Loan and Debt (the Debt/Loan tab) do.
    nonisolated static func isExcludedFromReport(_ type: CategoryType) -> Bool {
        type == .debtLoan
    }

    /// The unarchived wallet of the most recently entered transaction, or else the first wallet in the user's order.
    /// A new wallet's Starting balance doesn't count as use.
    private static func lastUsedWallet(in context: ModelContext) -> Wallet? {
        let system = CategoryType.system.rawValue
        var lastEntered = FetchDescriptor<Transaction>(
            predicate: #Predicate {
                $0.wallet?.isArchived == false && $0.category?.typeRaw != system && $0.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        lastEntered.fetchLimit = 1
        let recent = Log.store.attempt("Reading the last-used wallet") { try context.fetch(lastEntered) }
        if let wallet = recent?.first?.wallet {
            return wallet
        }
        var firstWallet = Wallet.unarchived
        firstWallet.fetchLimit = 1
        return Log.store.attempt("Reading the first wallet") { try context.fetch(firstWallet) }?.first
    }
}
