import Foundation
import SwiftData

/// Account → Recently Deleted: the wallets, Recurring transactions and transactions deleted in the last 30 days, waiting
/// to be restored or removed for good. A deleted wallet is one item holding the transactions and Recurring transactions
/// deleted with it. Nothing in it counts in any balance, list, search or report.
struct RecentlyDeleted {
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
        func remove<Model: PersistentModel>(_ model: Model) {
            if removed.insert(model.persistentModelID).inserted {
                context.delete(model)
            }
        }
        for wallet in wallets {
            // A wallet's Recurring transactions go with it, as its transactions do, even if deleted on their own.
            for schedule in wallet.recurringTransactions ?? [] {
                remove(schedule)
            }
            for transaction in wallet.transactions ?? [] {
                remove(transaction)
            }
            // A Card is only offered on its paying wallet's transactions, so with the wallet gone it has no use left.
            for card in wallet.cards ?? []
            where (card.transactions ?? []).allSatisfy({ removed.contains($0.persistentModelID) }) {
                context.delete(card)
            }
            context.delete(wallet)
        }
        for schedule in recurring {
            remove(schedule)
        }
        for transaction in transactions {
            remove(transaction)
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
}

extension RecentlyDeletedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDeleted: String(localized: "It isn't in Recently Deleted.")
        case .walletIsDeleted: String(localized: "Its wallet is in Recently Deleted. Restore the wallet first.")
        case .deletedWithWallet: String(localized: "It was deleted with its wallet. Restore or delete the wallet instead.")
        case .loanOrDebtIsForgiven: String(localized: "Its Loan or Debt was forgiven since. Un-forgive it first.")
        }
    }
}

extension Wallet {
    /// Whether the wallet is in Recently Deleted.
    var isInRecentlyDeleted: Bool { deletedAt != nil }

    /// Deletes the wallet: moves it, every transaction in it and its Recurring transactions to Recently Deleted as one
    /// item. Due Recurring transactions are made first, so no due day is lost. It leaves the Total, every list and every
    /// picker. A transfer's other half in another wallet stays where it is. Saves.
    func delete(at now: Date = .now) throws {
        let schedules = (recurringTransactions ?? []).filter { !$0.isInRecentlyDeleted }
        if let context = modelContext {
            for schedule in schedules {
                schedule.makeDueTransactions(through: CalendarDay(now), in: context)
            }
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
        try modelContext?.save()
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
    func restore(today: CalendarDay = .today) throws {
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
        try modelContext?.save()
    }

    /// Delete Forever: removes the wallet in Recently Deleted and every transaction in it for good, with the Cards
    /// paid from it. Saves.
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
    func restore(today: CalendarDay = .today) throws {
        if let restoreBlocker { throw restoreBlocker }
        skipOccurrences(through: today)
        deletedAt = nil
        try modelContext?.save()
    }

    /// Delete Forever: removes a schedule deleted on its own for good. The transactions it made stay as ordinary ones.
    /// Saves.
    func deleteForever(in context: ModelContext) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        guard !deletedWithWallet else { throw RecentlyDeletedError.deletedWithWallet }
        try RecentlyDeleted.removeForGood(wallets: [], transactions: [], recurring: [self], in: context)
    }
}

extension Card {
    /// Whether the Card's paying wallet is in Recently Deleted. The Card waits out of sight with it: it leaves the
    /// Cards list and pickers, and comes back when the wallet is restored.
    var isPaidFromDeletedWallet: Bool { payingWallet?.isInRecentlyDeleted == true }
}

extension Transaction {
    /// Every transaction outside Recently Deleted: what every balance, list, search and report counts.
    static var notDeleted: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil })
    }

    /// Whether the transaction is in Recently Deleted.
    var isInRecentlyDeleted: Bool { deletedAt != nil }

    /// Why this transaction in Recently Deleted can't be restored on its own, or `nil` when it can.
    var restoreBlocker: RecentlyDeletedError? {
        guard isInRecentlyDeleted else { return .notDeleted }
        if deletedWithWallet { return .deletedWithWallet }
        if wallet?.isInRecentlyDeleted == true { return .walletIsDeleted }
        if paysForgivenLoanOrDebt { return .loanOrDebtIsForgiven }
        return nil
    }

    /// Whether this is a Debt Collection or Repayment linked to a Loan or Debt that is forgiven.
    private var paysForgivenLoanOrDebt: Bool {
        let role = category?.lockedRole
        guard role == .debtCollection || role == .repayment, let link = linkID, let context = modelContext else {
            return false
        }
        let linked = FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID == link && $0.deletedAt == nil })
        return ((try? context.fetch(linked)) ?? []).contains { $0.isForgiven && $0.loanOrDebtKind?.paymentRole == role }
    }

    /// Brings a transaction deleted on its own back from Recently Deleted, linked as before. One deleted with its
    /// wallet comes back only with the wallet, one whose wallet is in the bin waits for the wallet, and a payment
    /// whose Loan or Debt was forgiven since waits for it to be un-forgiven. A deposit moved into an Expense takes its
    /// Reimbursement back off the Expense (``takeBackMovedInReimbursements()``). Saves.
    func restore() throws {
        if let restoreBlocker { throw restoreBlocker }
        deletedAt = nil
        takeBackMovedInReimbursements()
        try modelContext?.save()
    }

    /// The payments on this Loan or Debt waiting in Recently Deleted. Restoring one brings it back against this Loan
    /// or Debt, so until then they still hold its wallet, category and lowest amount in place.
    var paymentsInRecentlyDeleted: [Transaction] {
        guard let kind = loanOrDebtKind, let link = linkID, let context = modelContext else { return [] }
        let deleted = FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID == link && $0.deletedAt != nil })
        return ((try? context.fetch(deleted)) ?? []).filter { $0.category?.lockedRole == kind.paymentRole }
    }

    /// Delete Forever: removes a transaction deleted on its own for good. Saves.
    func deleteForever(in context: ModelContext) throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        guard !deletedWithWallet else { throw RecentlyDeletedError.deletedWithWallet }
        try RecentlyDeleted.removeForGood(wallets: [], transactions: [self], in: context)
    }
}

extension Sequence where Element == Transaction {
    /// The transactions outside Recently Deleted.
    var notDeleted: [Transaction] { filter { !$0.isInRecentlyDeleted } }
}
