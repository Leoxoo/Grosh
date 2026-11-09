import Foundation
import SwiftData

/// "Suggest defaults": the one place the starting values of the Add Transaction sheet, a Transfer and Adjust Balance
/// come from. The sheets make no default-value decisions of their own.
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

    /// The starting values of a new transfer, dated `today`: from the ``wallet(viewing:in:)`` (the wallet the
    /// Transactions tab is showing, or else the last-used one), to the first other unarchived wallet in the user's
    /// order.
    static func suggestTransfer(on today: CalendarDay, viewing viewed: Wallet? = nil, in context: ModelContext) -> TransferDraft {
        var draft = TransferDraft(day: today)
        draft.from = wallet(viewing: viewed, in: context)
        let wallets = Log.store.attempt("Reading the unarchived wallets") { try context.fetch(Wallet.unarchived) } ?? []
        draft.to = wallets.first { $0 != draft.from }
        return draft
    }

    /// The starting values of Adjust Balance, dated `today`: in the ``wallet(viewing:in:)`` (the wallet the
    /// screen shows, or else the last-used one), with its real balance at the recorded one, from `balances` on `today`.
    static func suggestBalanceAdjustment(
        on today: CalendarDay, viewing viewed: Wallet? = nil, balances: WalletBalances, in context: ModelContext
    ) throws -> BalanceAdjustmentDraft {
        let wallet = wallet(viewing: viewed, in: context)
        return BalanceAdjustmentDraft(
            wallet: wallet, day: today, recordedBalance: wallet.map(balances.balance(of:)),
            defaultReasons: try BalanceAdjustmentDraft.defaultReasons(in: context)
        )
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
