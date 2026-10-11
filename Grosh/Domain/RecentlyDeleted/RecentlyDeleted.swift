import Foundation
import SwiftData

/// Account → Recently Deleted: the wallets and transactions deleted in the last 30 days, waiting to be restored or
/// removed for good. A deleted wallet is one item holding the transactions deleted with it. Nothing in it counts in
/// any balance, list, search or report.
struct RecentlyDeleted {
    /// How long an item waits before it is removed for good.
    static let keptDays = 30

    /// The wallets in the bin, the most recently deleted first.
    let wallets: [Wallet]
    /// The transactions deleted on their own, the most recently deleted first. Those deleted with their wallet are
    /// part of the wallet's item instead.
    let transactions: [Transaction]

    /// Every wallet in the bin.
    static var deletedWallets: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt != nil })
    }

    /// Every transaction deleted on its own, not with its wallet.
    static var deletedTransactions: FetchDescriptor<Transaction> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt != nil && !$0.deletedWithWallet })
    }

    /// The bin made of `wallets` and `transactions` (what ``deletedWallets`` and ``deletedTransactions`` fetch).
    init(wallets: some Sequence<Wallet>, transactions: some Sequence<Transaction>) {
        self.wallets = wallets.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
        self.transactions = transactions.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    /// The bin as it is in `context`.
    init(in context: ModelContext) throws {
        self.init(
            wallets: try context.fetch(Self.deletedWallets), transactions: try context.fetch(Self.deletedTransactions)
        )
    }

    var isEmpty: Bool { wallets.isEmpty && transactions.isEmpty }

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

    /// Removes for good every item that has waited its 30 days by `now`: a wallet with all its transactions, and each
    /// transaction deleted on its own. The app does this when it opens; nothing runs in the background. Saves.
    static func purgeExpired(in context: ModelContext, now: Date = .now) throws {
        let bin = try RecentlyDeleted(in: context)
        let expired = { (deletedAt: Date?) in deletedAt.map { Self.isExpired(since: $0, now: now) } ?? false }
        try removeForGood(
            wallets: bin.wallets.filter { expired($0.deletedAt) },
            transactions: bin.transactions.filter { expired($0.deletedAt) },
            in: context
        )
    }

    /// Empty Bin: removes every wallet and transaction in it for good. Saves.
    static func empty(in context: ModelContext) throws {
        let bin = try RecentlyDeleted(in: context)
        try removeForGood(wallets: bin.wallets, transactions: bin.transactions, in: context)
    }

    /// Removes `wallets`, each with every transaction in it and the Cards paid from it that are left with none, and
    /// `transactions` from the store. Saves.
    fileprivate static func removeForGood(
        wallets: [Wallet], transactions: [Transaction], in context: ModelContext
    ) throws {
        var removed = Set<PersistentIdentifier>()
        func remove(_ transaction: Transaction) {
            if removed.insert(transaction.persistentModelID).inserted {
                context.delete(transaction)
            }
        }
        for wallet in wallets {
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
        transactions.forEach(remove)
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
}

extension RecentlyDeletedError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notDeleted: String(localized: "It isn't in Recently Deleted.")
        case .walletIsDeleted: String(localized: "Its wallet is in Recently Deleted. Restore the wallet first.")
        case .deletedWithWallet: String(localized: "It was deleted with its wallet. Restore or delete the wallet instead.")
        }
    }
}

extension Wallet {
    /// Whether the wallet is in Recently Deleted.
    var isInRecentlyDeleted: Bool { deletedAt != nil }

    /// Deletes the wallet: moves it and every transaction in it to Recently Deleted as one item. It leaves the Total,
    /// every list and every picker. A transfer's other half in another wallet stays where it is. Saves.
    func delete(at now: Date = .now) throws {
        deletedAt = now
        for transaction in (transactions ?? []).notDeleted {
            transaction.deletedAt = now
            transaction.deletedWithWallet = true
        }
        try modelContext?.save()
    }

    /// The transactions that went to Recently Deleted with this wallet, newest first: what its item holds.
    var transactionsDeletedWithIt: [Transaction] {
        (transactions ?? []).filter { $0.isInRecentlyDeleted && $0.deletedWithWallet }.inListOrder()
    }

    /// Brings the wallet back from Recently Deleted with the transactions deleted with it. Transactions deleted on
    /// their own before it stay in the bin. Saves.
    func restore() throws {
        guard isInRecentlyDeleted else { throw RecentlyDeletedError.notDeleted }
        for transaction in transactionsDeletedWithIt {
            transaction.deletedAt = nil
            transaction.deletedWithWallet = false
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

    /// Why this transaction in Recently Deleted can't be restored or removed on its own, or `nil` when it can.
    var restoreBlocker: RecentlyDeletedError? {
        guard isInRecentlyDeleted else { return .notDeleted }
        if deletedWithWallet { return .deletedWithWallet }
        if wallet?.isInRecentlyDeleted == true { return .walletIsDeleted }
        return nil
    }

    /// Brings a transaction deleted on its own back from Recently Deleted, linked as before. One deleted with its
    /// wallet comes back only with the wallet, and one whose wallet is in the bin waits for the wallet. Saves.
    func restore() throws {
        if let restoreBlocker { throw restoreBlocker }
        deletedAt = nil
        try modelContext?.save()
    }

    /// Whether a payment on this Loan or Debt waits in Recently Deleted. Restoring it brings it back against this
    /// Loan or Debt, so until then the payment still holds its wallet and category in place.
    var hasPaymentsInRecentlyDeleted: Bool {
        guard let kind = loanOrDebtKind, let link = linkID, let context = modelContext else { return false }
        let deleted = FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID == link && $0.deletedAt != nil })
        return ((try? context.fetch(deleted)) ?? []).contains { $0.category?.lockedRole == kind.paymentRole }
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
