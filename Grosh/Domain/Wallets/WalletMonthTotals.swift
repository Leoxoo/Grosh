import Foundation
import os
import SwiftData

/// Keeps the saved month totals (``WalletMonthTotal``) right and reads them (ADR-0013): for each wallet and calendar
/// month, the net of that month's transactions outside Recently Deleted. Every month is saved the same way, the
/// current one and those ahead included; only reading a balance knows which day it is.
///
/// A change to what a balance counts marks its wallet-months dirty (``Transaction/changeCounted(_:)``). Right after
/// each save of a context ``recountAfterEachSave(of:)`` was given, those months are counted again from their
/// transactions and their marks cleared, in a second save. A month still dirty when the totals are next read, as after
/// the app stopped between the two saves, is counted then (``read(through:in:)``).
enum WalletMonthTotals {
    /// The format the totals are counted in (``WalletMonthTotalFormat``). Raise it when what a total holds changes:
    /// the next launch rebuilds them all.
    static let formatVersion = 1

    // MARK: Counting after each save

    /// Counts the dirty months of `context` again right after each of its saves, before the save returns: no
    /// background work. The store does this for its main context when it opens (``StoreOpening/prepare(_:)``).
    /// Asking again for the same context changes nothing.
    static func recountAfterEachSave(of context: ModelContext) {
        _ = saves
        counting = counting.filter { $0.value.context != nil }
        counting[ObjectIdentifier(context)] = Counted(context: context)
    }

    private struct Counted {
        weak var context: ModelContext?
    }

    /// The contexts whose saves are followed by a count, by identity.
    private static var counting: [ObjectIdentifier: Counted] = [:]
    /// The contexts being counted now: the count's own save is not followed by another.
    private static var recounting: Set<ObjectIdentifier> = []

    /// One observer for every context's saves, made the first time a context is counted. A save off the main thread
    /// isn't followed by a count; its months are counted when the totals are next read.
    private static let saves: any NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: ModelContext.didSave, object: nil, queue: nil
    ) { notification in
        guard Thread.isMainThread else { return }
        let saved = SavedContext(notification)
        MainActor.assumeIsolated {
            if let context = saved.context { countAfterSave(of: context) }
        }
    }

    /// The context a save notification came from, handed to the main actor it was posted on.
    nonisolated private struct SavedContext: @unchecked Sendable {
        weak var context: ModelContext?

        init(_ notification: Notification) {
            context = notification.object as? ModelContext
        }
    }

    private static func countAfterSave(of context: ModelContext) {
        let id = ObjectIdentifier(context)
        guard counting[id]?.context === context, !recounting.contains(id) else { return }
        recounting.insert(id)
        defer { recounting.remove(id) }
        Log.store.attempt("Counting the saved month totals again") {
            try countDirtyMonths(in: context)
        }
    }

    /// Counts every dirty wallet-month of `context` again from its transactions and clears its mark. Saves when there
    /// was one; does nothing otherwise.
    static func countDirtyMonths(in context: ModelContext) throws {
        let marks = try context.fetch(FetchDescriptor<DirtyWalletMonth>()).filter { !$0.isDeleted }
        guard !marks.isEmpty else { return }
        for mark in marks {
            if let wallet = mark.wallet, !wallet.isDeleted {
                let transactions = try context.fetch(counted(in: wallet, monthRaw: mark.monthRaw))
                save(transactions.reduce(0) { $0 + $1.netCents }, as: mark.monthRaw, of: wallet, in: context)
            }
            context.delete(mark)
        }
        try context.save()
    }

    /// The transactions `wallet`'s total for the month `monthRaw` (`yyyymm`) adds up: those dated in it outside
    /// Recently Deleted.
    private static func counted(in wallet: Wallet, monthRaw: Int) -> FetchDescriptor<Transaction> {
        let id = wallet.persistentModelID
        let first = monthRaw * 100
        let last = monthRaw * 100 + 99
        return FetchDescriptor(predicate: #Predicate {
            $0.wallet?.persistentModelID == id && $0.dayRaw >= first && $0.dayRaw <= last && $0.deletedAt == nil
        })
    }

    /// Makes `netCents` the saved total of `wallet` for the month `monthRaw`. A month that nets to nothing and had no
    /// total yet gets none.
    private static func save(_ netCents: Int, as monthRaw: Int, of wallet: Wallet, in context: ModelContext) {
        if let total = (wallet.monthTotals ?? []).first(where: { !$0.isDeleted && $0.monthRaw == monthRaw }) {
            if total.netCents != netCents { total.netCents = netCents }
        } else if netCents != 0 {
            let total = WalletMonthTotal(monthRaw: monthRaw, netCents: netCents)
            context.insert(total)
            total.wallet = wallet
        }
    }

    // MARK: Rebuilding

    /// Builds every saved total again from the transactions when the store's format (``WalletMonthTotalFormat``) is
    /// missing or isn't ``formatVersion``: on the first launch after an update that brought the totals or changed
    /// them. Reads every transaction, so it runs once, in ``StoreOpening/prepare(_:)``, before any screen reads. Saves
    /// when it rebuilt.
    static func rebuildIfOutdated(in context: ModelContext) throws {
        let formats = try context.fetch(FetchDescriptor<WalletMonthTotalFormat>())
        guard formats.count != 1 || formats.first?.version != formatVersion else { return }
        try rebuild(in: context)
        try context.save()
    }

    /// Replaces every saved total with one counted from the transactions in `context`, its unsaved changes included,
    /// clears every dirty mark, and records the format as ``formatVersion``. Doesn't save.
    static func rebuild(in context: ModelContext) throws {
        for total in try context.fetch(FetchDescriptor<WalletMonthTotal>()) {
            context.delete(total)
        }
        for mark in try context.fetch(FetchDescriptor<DirtyWalletMonth>()) {
            context.delete(mark)
        }
        for (month, netCents) in try fullCount(in: context) where netCents != 0 {
            let total = WalletMonthTotal(monthRaw: month.monthRaw, netCents: netCents)
            context.insert(total)
            total.wallet = month.wallet
        }
        let formats = try context.fetch(FetchDescriptor<WalletMonthTotalFormat>())
        for extra in formats.dropFirst() {
            context.delete(extra)
        }
        if let format = formats.first {
            format.version = formatVersion
        } else {
            context.insert(WalletMonthTotalFormat(version: formatVersion))
        }
    }

    /// One wallet-month, keyed by the wallet's identity.
    struct WalletMonth: Hashable {
        let wallet: Wallet
        let monthRaw: Int

        static func == (lhs: WalletMonth, rhs: WalletMonth) -> Bool {
            lhs.wallet === rhs.wallet && lhs.monthRaw == rhs.monthRaw
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(wallet))
            hasher.combine(monthRaw)
        }
    }

    /// The net of each wallet-month, counted from every transaction in `context` outside Recently Deleted, its unsaved
    /// changes included: what the saved totals should hold. One pass over every transaction.
    private static func fullCount(in context: ModelContext) throws -> [WalletMonth: Int] {
        var net: [WalletMonth: Int] = [:]
        for transaction in try context.fetch(Transaction.notDeleted) where !transaction.isDeleted {
            guard let wallet = transaction.wallet, !wallet.isDeleted else { continue }
            net[WalletMonth(wallet: wallet, monthRaw: transaction.dayRaw / 100), default: 0] += transaction.netCents
        }
        return net
    }

    // MARK: Checking

    /// A wallet-month whose saved total isn't what its transactions add up to.
    struct Mismatch {
        let wallet: Wallet
        let monthRaw: Int
        let savedCents: Int
        let countedCents: Int
    }

    /// Every wallet-month in `context` whose saved total differs from a full count of its transactions, unsaved
    /// changes included. A month marked dirty is waiting to be counted, so it is left out. Reads every transaction:
    /// for the tests, which check every test's store, and the Debug launch (``logMismatches(in:)``).
    static func mismatches(in context: ModelContext) throws -> [Mismatch] {
        let counted = try fullCount(in: context)
        var saved: [WalletMonth: Int] = [:]
        for total in try context.fetch(FetchDescriptor<WalletMonthTotal>()) where !total.isDeleted {
            guard let wallet = total.wallet, !wallet.isDeleted else { continue }
            saved[WalletMonth(wallet: wallet, monthRaw: total.monthRaw), default: 0] += total.netCents
        }
        var dirty: Set<WalletMonth> = []
        for mark in try context.fetch(FetchDescriptor<DirtyWalletMonth>()) where !mark.isDeleted {
            if let wallet = mark.wallet { dirty.insert(WalletMonth(wallet: wallet, monthRaw: mark.monthRaw)) }
        }
        return Set(counted.keys).union(saved.keys).subtracting(dirty).compactMap { month in
            let savedCents = saved[month] ?? 0
            let countedCents = counted[month] ?? 0
            guard savedCents != countedCents else { return nil }
            return Mismatch(
                wallet: month.wallet, monthRaw: month.monthRaw, savedCents: savedCents, countedCents: countedCents
            )
        }
        .sorted { ($0.wallet.name, $0.monthRaw) < ($1.wallet.name, $1.monthRaw) }
    }

    /// Logs an error when a saved total differs from its transactions (``mismatches(in:)``): a change that marked no
    /// month. Debug builds check once at launch; the shipped app doesn't read every transaction for it.
    static func logMismatches(in context: ModelContext) {
        guard let mismatches = Log.store.attempt("Checking the saved month totals", { try mismatches(in: context) }),
            !mismatches.isEmpty
        else { return }
        Log.store.error(
            "Saved month totals differ from their transactions in \(mismatches.count, privacy: .public) wallet-months"
        )
    }

    // MARK: Reading

    /// Every wallet's saved totals up to and including `month`, after counting any month still dirty (which saves).
    /// What a balance adds up: a wallet's balance today is the sum of its totals through this month, less this month's
    /// transactions dated after today (ADR-0013).
    static func read(through month: CalendarMonth, in context: ModelContext) throws -> [WalletMonthTotal] {
        try countDirtyMonths(in: context)
        let last = month.year * 100 + month.month
        return try context.fetch(FetchDescriptor<WalletMonthTotal>(predicate: #Predicate { $0.monthRaw <= last }))
    }
}
