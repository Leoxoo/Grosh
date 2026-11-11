import Foundation
import SwiftData

/// Account → Recently Deleted: the wallets, Recurring transactions and transactions deleted in the last 30 days, waiting
/// to be restored or removed for good. A deleted wallet is one item holding the transactions and Recurring transactions
/// deleted with it. Nothing in it counts in any balance, list, search or report.
nonisolated struct RecentlyDeleted {
    /// How long an item waits before it is removed for good.
    static let keptDays = 30

    /// The wallets in the bin, the most recently deleted first.
    let wallets: [Wallet]
    /// The Recurring transactions deleted on their own, the most recently deleted first. Those deleted with their
    /// wallet are part of the wallet's item instead.
    let recurring: [RecurringTransaction]
    /// The transactions deleted on their own, the most recently deleted first. Those deleted with their wallet are
    /// part of the wallet's item instead.
    let transactions: [Transaction]

    /// Every wallet in the bin.
    static var deletedWallets: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt != nil })
    }

    /// Every Recurring transaction deleted on its own, not with its wallet.
    static var deletedRecurring: FetchDescriptor<RecurringTransaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt != nil && !$0.deletedWithWallet })
    }

    /// Every transaction deleted on its own, not with its wallet.
    static var deletedTransactions: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt != nil && !$0.deletedWithWallet })
    }

    /// The bin made of `wallets`, `transactions` and `recurring` (what the descriptors above fetch).
    init(
        wallets: some Sequence<Wallet>,
        transactions: some Sequence<Transaction>,
        recurring: [RecurringTransaction] = []
    ) {
        self.wallets = wallets.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        self.recurring = recurring.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        self.transactions = transactions.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// The bin as it is in `context`.
    init(in context: ModelContext) throws {
        self.init(
            wallets: try context.fetch(Self.deletedWallets),
            transactions: try context.fetch(Self.deletedTransactions),
            recurring: try context.fetch(Self.deletedRecurring)
        )
    }

    var isEmpty: Bool { wallets.isEmpty && recurring.isEmpty && transactions.isEmpty }

    /// How many days an item deleted at `deletedAt` has left at `now` before it is removed for good, rounded up:
    /// 30 straight after deleting, 1 on its last day, 0 once it is due.
    static func daysLeft(since deletedAt: Date, now: Date) -> Int {
        let remaining = deletedAt.addingTimeInterval(keptInterval).timeIntervalSince(now)
        return max(0, Int((remaining / secondsPerDay).rounded(.up)))
    }

    /// Whether an item deleted at `deletedAt` has waited its 30 days by `now`.
    static func isExpired(since deletedAt: Date, now: Date) -> Bool {
        deletedAt.addingTimeInterval(keptInterval) <= now
    }

    /// Removes for good every item that has waited its 30 days by `now`: a wallet with all its transactions and
    /// Recurring transactions, and each transaction or Recurring transaction deleted on its own. The app does this when
    /// it opens; nothing runs in the background. Saves.
    static func purgeExpired(in context: ModelContext, now: Date = .now) throws {
        let bin = try RecentlyDeleted(in: context)
        let expired = { (deletedAt: Date?) in deletedAt.map { Self.isExpired(since: $0, now: now) } ?? false }
        try removeForGood(
            wallets: bin.wallets.filter { expired($0.deletedAt) },
            transactions: bin.transactions.filter { expired($0.deletedAt) },
            recurring: bin.recurring.filter { expired($0.deletedAt) },
            in: context
        )
    }

    /// Empty Bin: removes every wallet, Recurring transaction and transaction in it for good. Saves.
    static func empty(in context: ModelContext) throws {
        let bin = try RecentlyDeleted(in: context)
        try removeForGood(wallets: bin.wallets, transactions: bin.transactions, recurring: bin.recurring, in: context)
    }

    /// Removes `wallets`, each with every transaction and Recurring transaction in it and the Cards paid from it that
    /// are left with none, and `recurring` and `transactions` from the store. Saves.
    fileprivate static func removeForGood(
        wallets: [Wallet],
        transactions: [Transaction],
        recurring: [RecurringTransaction] = [],
        in context: ModelContext
    ) throws {
        var removed = Set<PersistentIdentifier>()
        var paidBack: [Transaction] = []
        func remove(model: some PersistentModel) {
            if removed.insert(model.persistentModelID).inserted {
                context.delete(model)
            }
        }
        // An Expense whose last payback is removed for good is no longer paid back elsewhere.
        func removeTransaction(_ transaction: Transaction) {
            if let expense = transaction.paidBackExpense {
                paidBack.append(expense)
            }
            remove(model: transaction)
        }
        for wallet in wallets {
            // A wallet's Recurring transactions go with it, as its transactions do, even if deleted on their own.
            for schedule in wallet.recurringTransactions ?? [] {
                remove(model: schedule)
            }
            for transaction in wallet.transactions ?? [] {
                removeTransaction(transaction)
            }
            // A Card is only offered on its paying wallet's transactions, so with the wallet gone it has no use left.
            for card in wallet.cards ?? []
            where (card.transactions ?? []).allSatisfy({ removed.contains($0.persistentModelID) }) {
                context.delete(card)
            }
            context.delete(wallet)
        }
        for schedule in recurring {
            remove(model: schedule)
        }
        for transaction in transactions {
            removeTransaction(transaction)
        }
        for expense in paidBack where !removed.contains(expense.persistentModelID) {
            expense.forgetPaybacks(removedForGood: removed)
        }
        try context.save()
    }

    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
    private static var keptInterval: TimeInterval { TimeInterval(keptDays) * secondsPerDay }
}

/// Why something in Recently Deleted can't be restored or removed on its own.
nonisolated enum RecentlyDeletedError: Error, Equatable {
    /// The item isn't in Recently Deleted.
    case notDeleted
    /// A transaction whose wallet is in Recently Deleted waits for the wallet to be restored first.
    case walletIsDeleted
    /// A transaction deleted with its wallet is restored or removed with it.
    case deletedWithWallet
    /// A payment whose Loan or Debt was forgiven since it was deleted would be counted twice: un-forgive it first.
    case loanOrDebtIsForgiven
    /// What the item is linked to couldn't be read, so whether it may come back is unknown, and it stays in the bin.
    case couldntCheck
}

extension RecentlyDeletedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDeleted: String(localized: Strings.RecentlyDeleted.notDeleted)
        case .walletIsDeleted: String(localized: Strings.RecentlyDeleted.walletIsDeleted)
        case .deletedWithWallet: String(localized: Strings.RecentlyDeleted.deletedWithWallet)
        case .loanOrDebtIsForgiven: String(localized: Strings.RecentlyDeleted.loanOrDebtIsForgiven)
        case .couldntCheck: String(localized: Strings.RecentlyDeleted.couldntCheck)
        }
    }
}

extension Wallet {
    /// Deletes the wallet: moves it, every transaction in it and its Recurring transactions to Recently Deleted as one
    /// item. Due Recurring transactions are made first, so no due day is lost. It leaves the Total, every list and every
    /// picker. A transfer's other half in another wallet stays where it is. Saves.
    func delete(at now: Date = .now) throws {
        let context = try storeContext()
        let schedules = (recurringTransactions ?? []).filter { !$0.isInRecentlyDeleted }
        for schedule in schedules {
            schedule.makeDueTransactions(through: CalendarDay(now), in: context)
        }
        deletedAt = now
        for transaction in (transactions ?? []).notDeleted {
            transaction.deletedAt = now
            transaction.deletedWithWallet = true
        }
        for schedule in schedules {
            schedule.deletedAt = now
            schedule.deletedWithWallet = true
        }
        try context.save()
    }

    /// The transactions that went to Recently Deleted with this wallet, newest first: what its item holds.
    var transactionsDeletedWithIt: [Transaction] {
        (transactions ?? []).filter { $0.isInRecentlyDeleted && $0.deletedWithWallet }.inListOrder()
    }

    /// The Recurring transactions that went to Recently Deleted with this wallet, oldest first: the rest of its item.
    var recurringDeletedWithIt: [RecurringTransaction] {
        (recurringTransactions ?? [])
            .filter { $0.isInRecentlyDeleted && $0.deletedWithWallet }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Brings the wallet back from Recently Deleted with the transactions and Recurring transactions deleted with it.
    /// Transactions deleted on their own before it stay in the bin. Its Recurring transactions skip what fell due while
    /// it was away, so nothing is backfilled. Saves.
    @MainActor
    func restore(today: CalendarDay) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        for transaction in transactionsDeletedWithIt {
            transaction.deletedAt = nil
            transaction.deletedWithWallet = false
        }
        for schedule in recurringDeletedWithIt {
            schedule.deletedAt = nil
            schedule.deletedWithWallet = false
            schedule.skipOccurrences(through: today)
        }
        deletedAt = nil
        try saveToStore()
    }

    /// Delete Forever: removes the wallet in Recently Deleted for good, with every transaction and Recurring transaction
    /// in it and the Cards paid from it that are left with none. Saves.
    func deleteForever(in context: ModelContext) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        try RecentlyDeleted.removeForGood(wallets: [self], transactions: [], in: context)
    }
}

extension RecurringTransaction {
    /// Why this schedule in Recently Deleted can't be restored on its own, or `nil` when it can.
    var restoreBlocker: RecentlyDeletedError? {
        guard isInRecentlyDeleted else { return .notDeleted }
        if deletedWithWallet { return .deletedWithWallet }
        if wallet?.isInRecentlyDeleted == true { return .walletIsDeleted }
        return nil
    }

    /// Brings a schedule deleted on its own back from Recently Deleted, with its settings. What fell due while it was
    /// away is not made: it is skipped through `today`, as saving a schedule today skips the days before it. Saves.
    @MainActor
    func restore(today: CalendarDay) throws {
        if let restoreBlocker { throw restoreBlocker }
        skipOccurrences(through: today)
        deletedAt = nil
        try saveToStore()
    }

    /// Delete Forever: removes a schedule deleted on its own for good. The transactions it made stay as ordinary ones.
    /// Saves.
    func deleteForever(in context: ModelContext) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        guard !deletedWithWallet else { throw RecentlyDeletedError.deletedWithWallet }
        try RecentlyDeleted.removeForGood(wallets: [], transactions: [], recurring: [self], in: context)
    }
}

extension Transaction {
    /// Every transaction outside Recently Deleted: what every balance, list, search and report counts.
    static var notDeleted: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil })
    }

    /// Why this transaction in Recently Deleted can't be restored on its own, or `nil` when it can. One deleted with its
    /// wallet comes back only with the wallet, one whose wallet is in the bin waits for the wallet, and a payment
    /// whose Loan or Debt was forgiven since waits for it to be un-forgiven (``paysForgivenLoanOrDebt(in:)``). A payment
    /// reads the store for that, so a screen asks once per row. When that read fails the answer is
    /// ``RecentlyDeletedError/couldntCheck``: the transaction stays in the bin rather than risk counting twice.
    func restoreBlocker() -> RecentlyDeletedError? {
        guard isInRecentlyDeleted, let context = modelContext else { return .notDeleted }
        if deletedWithWallet { return .deletedWithWallet }
        if wallet?.isInRecentlyDeleted == true { return .walletIsDeleted }
        do {
            if try paysForgivenLoanOrDebt(in: context) { return .loanOrDebtIsForgiven }
        } catch {
            Log.store.failed("Reading the transactions linked to a payment", error)
            return .couldntCheck
        }
        return nil
    }

    /// Brings a transaction deleted on its own back from Recently Deleted, linked as before, unless its
    /// ``restoreBlocker()`` says why not. A deposit moved into an Expense takes its Reimbursement back off the Expense
    /// (``takeBackMovedInReimbursements()``). Saves.
    func restore() throws {
        if let blocker = restoreBlocker() { throw blocker }
        deletedAt = nil
        try takeBackMovedInReimbursements()
        try saveToStore()
    }

    /// Delete Forever: removes a transaction deleted on its own for good. Saves.
    func deleteForever(in context: ModelContext) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        guard !deletedWithWallet else { throw RecentlyDeletedError.deletedWithWallet }
        try RecentlyDeleted.removeForGood(wallets: [], transactions: [self], in: context)
    }
}

nonisolated extension Sequence where Element == Transaction {
    /// The transactions outside Recently Deleted.
    var notDeleted: [Transaction] { filter { !$0.isInRecentlyDeleted } }
}
