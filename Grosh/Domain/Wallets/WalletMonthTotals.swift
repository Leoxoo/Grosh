import Foundation
import os
import SwiftData

/// Keeps the saved month totals (``WalletMonthTotal``) right and reads them (ADR-0013): for each wallet and calendar
/// month, the net of that month's transactions outside Recently Deleted. Every month is saved the same way, the
/// current one and those ahead included; only reading a balance knows which day it is.
///
/// A change to what a balance counts marks its wallet-months dirty (``Transaction/changeCounted(_:)``). As each save
/// of a context ``countInEachSave(of:)`` was given begins, those months are counted again from their transactions and
/// their marks cleared, so the totals go into the same save as the change. A month still dirty when the totals are
/// read, as after a save nothing counted, is counted then, in memory, without saving (``read(through:in:)``), and saved
/// by the next save.
enum WalletMonthTotals {
    /// The format the totals are counted in (``WalletMonthTotalFormat``). Raise it when what a total holds changes:
    /// the next launch rebuilds them all.
    static let formatVersion = 1

    // MARK: Counting in each save

    /// Counts the dirty months of `context` again as each of its saves begins, so the totals they change go into that
    /// same save: no background work, and no second save that every other observer of the store's saves
    /// (``StoreSaves``, ``NotDeletedTransactions``) would see inside the first. `willSave` is posted before the context
    /// hands its changes to the store, so what the count changes is saved with them. The store does this for its main
    /// context when it opens (``StoreOpening/prepare(_:)``); a context nothing counts, or a save off the main thread,
    /// leaves its months dirty, counted in memory when the totals are read and saved by the next counted save.
    static func countInEachSave(of context: ModelContext) {
        let saving = SavingContext(context: context)
        _ = NotificationCenter.default.addObserver(forName: ModelContext.willSave, object: context, queue: nil) { _ in
            guard Thread.isMainThread else { return }
            MainActor.assumeIsolated {
                guard let context = saving.context else { return }
                Log.store.attempt("Counting the saved month totals again") {
                    _ = try countDirty(in: context)
                }
            }
        }
    }

    /// The counted context, held without keeping it alive, for the main actor its saves are posted on.
    nonisolated private struct SavingContext: @unchecked Sendable {
        weak var context: ModelContext?
    }

    /// Counts every dirty wallet-month of `context` again from its transactions and clears its mark. Saves when there
    /// was one; does nothing otherwise.
    static func countDirtyMonths(in context: ModelContext) throws {
        guard try countDirty(in: context) else { return }
        try context.save()
    }

    /// Counts every dirty wallet-month of `context` again into its saved total and clears its mark, and says whether
    /// there was one. Doesn't save.
    private static func countDirty(in context: ModelContext) throws -> Bool {
        let marks = try context.fetch(FetchDescriptor<DirtyWalletMonth>()).filter { !$0.isDeleted }
        guard !marks.isEmpty else { return false }
        for (wallet, months) in dirtyMonths(of: marks) {
            for (month, netCents) in try count(months, of: wallet, in: context) {
                save(netCents, as: month, of: wallet, in: context)
            }
        }
        for mark in marks {
            context.delete(mark)
        }
        return true
    }

    /// The dirty months of each wallet `marks` mark, leaving out a wallet removed for good in the context: its totals
    /// go with it.
    private static func dirtyMonths(of marks: [DirtyWalletMonth]) -> [(wallet: Wallet, months: Set<CalendarMonth>)] {
        var byWallet: [ObjectIdentifier: (wallet: Wallet, months: Set<CalendarMonth>)] = [:]
        for mark in marks {
            guard let wallet = mark.wallet, !wallet.isDeleted else { continue }
            byWallet[ObjectIdentifier(wallet), default: (wallet, [])].months.insert(mark.month)
        }
        return Array(byWallet.values)
    }

    /// The net of each of `wallet`'s `months`, counted from its transactions outside Recently Deleted in `context`, its
    /// unsaved changes included. One read, from the earliest of them to the latest: an edit marks one to four months.
    private static func count(
        _ months: Set<CalendarMonth>, of wallet: Wallet, in context: ModelContext
    ) throws -> [CalendarMonth: Int] {
        guard let first = months.min(), let last = months.max() else { return [:] }
        var net = Dictionary(uniqueKeysWithValues: months.map { ($0, 0) })
        for transaction in try context.fetch(counted(in: wallet, during: first...last)) where !transaction.isDeleted {
            net[CalendarMonth(transaction.day)]? += transaction.netCents
        }
        return net
    }

    /// The transactions of `wallet` dated in `months` outside Recently Deleted: what their saved totals add up.
    private static func counted(
        in wallet: Wallet, during months: ClosedRange<CalendarMonth>
    ) -> FetchDescriptor<Transaction> {
        let id = wallet.persistentModelID
        let first = months.lowerBound.firstDay.rawValue
        let last = months.upperBound.lastDay.rawValue
        return FetchDescriptor(predicate: #Predicate {
            $0.wallet?.persistentModelID == id && $0.dayRaw >= first && $0.dayRaw <= last && $0.deletedAt == nil
        })
    }

    /// Makes `netCents` the saved total of `wallet`'s `month`. A month that nets to nothing and had no total yet gets
    /// none.
    private static func save(_ netCents: Int, as month: CalendarMonth, of wallet: Wallet, in context: ModelContext) {
        if let total = (wallet.monthTotals ?? []).first(where: { !$0.isDeleted && $0.month == month }) {
            if total.netCents != netCents { total.netCents = netCents }
        } else if netCents != 0 {
            WalletMonthTotal.insert(netCents, for: month, of: wallet, in: context)
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
        let counted = try fullCount(in: context)
        for (walletMonth, netCents) in counted.nets where netCents != 0 {
            guard let wallet = counted.wallets[walletMonth.wallet] else { continue }
            WalletMonthTotal.insert(netCents, for: walletMonth.month, of: wallet, in: context)
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

    /// One wallet-month, keyed by the wallet's identity in its context, as ``WalletBalances`` keys its wallets.
    struct WalletMonth: Hashable {
        let wallet: ObjectIdentifier
        let month: CalendarMonth

        init(_ wallet: Wallet, _ month: CalendarMonth) {
            self.wallet = ObjectIdentifier(wallet)
            self.month = month
        }
    }

    /// The net of each wallet-month, counted from every transaction in `context` outside Recently Deleted, its unsaved
    /// changes included: what the saved totals should hold, and the wallets they belong to. One pass over every
    /// transaction.
    private static func fullCount(
        in context: ModelContext
    ) throws -> (nets: [WalletMonth: Int], wallets: [ObjectIdentifier: Wallet]) {
        var nets: [WalletMonth: Int] = [:]
        var wallets: [ObjectIdentifier: Wallet] = [:]
        for transaction in try context.fetch(Transaction.notDeleted) where !transaction.isDeleted {
            guard let wallet = transaction.wallet, !wallet.isDeleted else { continue }
            nets[WalletMonth(wallet, CalendarMonth(transaction.day)), default: 0] += transaction.netCents
            wallets[ObjectIdentifier(wallet)] = wallet
        }
        return (nets, wallets)
    }

    // MARK: Checking

    /// A wallet-month whose saved total isn't what its transactions add up to.
    struct Mismatch {
        let wallet: Wallet
        let month: CalendarMonth
        let savedCents: Int
        let countedCents: Int
    }

    /// Every wallet-month in `context` whose saved total differs from a full count of its transactions, unsaved
    /// changes included. A month marked dirty is waiting to be counted, so it is left out. Reads every transaction:
    /// for the tests, which check every test's store, and the Debug launch (``logMismatches(in:)``).
    static func mismatches(in context: ModelContext) throws -> [Mismatch] {
        var (counted, wallets) = try fullCount(in: context)
        var saved: [WalletMonth: Int] = [:]
        for total in try context.fetch(FetchDescriptor<WalletMonthTotal>()) where !total.isDeleted {
            guard let wallet = total.wallet, !wallet.isDeleted else { continue }
            saved[WalletMonth(wallet, total.month), default: 0] += total.netCents
            wallets[ObjectIdentifier(wallet)] = wallet
        }
        var dirty: Set<WalletMonth> = []
        for mark in try context.fetch(FetchDescriptor<DirtyWalletMonth>()) where !mark.isDeleted {
            if let wallet = mark.wallet { dirty.insert(WalletMonth(wallet, mark.month)) }
        }
        return Set(counted.keys).union(saved.keys).subtracting(dirty).compactMap { walletMonth in
            let savedCents = saved[walletMonth] ?? 0
            let countedCents = counted[walletMonth] ?? 0
            guard savedCents != countedCents, let wallet = wallets[walletMonth.wallet] else { return nil }
            return Mismatch(wallet: wallet, month: walletMonth.month, savedCents: savedCents, countedCents: countedCents)
        }
        .sorted { ($0.wallet.name, $0.month) < ($1.wallet.name, $1.month) }
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

    /// The net of every wallet-month up to and including `month`: its saved total or, for a month still dirty (as
    /// after a save nothing counted), its transactions counted now. What a balance adds up: a wallet's balance today is
    /// the sum of its months through this one, less this month's transactions dated after today (ADR-0013).
    ///
    /// Only reads, never saves: a screen reads it while it draws (``SavedWalletBalances``), when a save would tell every
    /// observer of the store's saves to draw again. A dirty month keeps its mark for the next save to count.
    static func read(through month: CalendarMonth, in context: ModelContext) throws -> [WalletMonth: Int] {
        let last = month.rawValue
        var net: [WalletMonth: Int] = [:]
        for total in try context.fetch(FetchDescriptor<WalletMonthTotal>(predicate: #Predicate { $0.monthRaw <= last })) {
            if let wallet = total.wallet { net[WalletMonth(wallet, total.month), default: 0] += total.netCents }
        }
        let marks = try context.fetch(FetchDescriptor<DirtyWalletMonth>()).filter { !$0.isDeleted }
        for (wallet, months) in dirtyMonths(of: marks) {
            for (dirty, netCents) in try count(months.filter { $0 <= month }, of: wallet, in: context) {
                net[WalletMonth(wallet, dirty)] = netCents
            }
        }
        return net
    }
}
