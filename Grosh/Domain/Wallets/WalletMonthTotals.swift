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
/// the app stopped between the two saves, is counted then, in memory, without saving (``read(through:in:)``), and
/// saved by the next save.
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
        counting[ObjectIdentifier(context)] = WeakContext(context: context)
    }

    /// A context held without keeping it alive.
    private struct WeakContext {
        weak var context: ModelContext?
    }

    /// The contexts whose saves are followed by a count, by identity.
    private static var counting: [ObjectIdentifier: WeakContext] = [:]
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
        guard try countDirty(in: context) else { return }
        try context.save()
    }

    /// Counts every dirty wallet-month of `context` again into its saved total and clears its mark, and says whether
    /// there was one. Doesn't save.
    private static func countDirty(in context: ModelContext) throws -> Bool {
        let marks = try context.fetch(FetchDescriptor<DirtyWalletMonth>()).filter { !$0.isDeleted }
        guard !marks.isEmpty else { return false }
        for (month, netCents) in try count(dirtyMonths(of: marks), in: context) {
            save(netCents, as: month, in: context)
        }
        for mark in marks {
            context.delete(mark)
        }
        return true
    }

    /// The wallet-months `marks` mark, leaving out a wallet removed for good in the context: its totals go with it.
    private static func dirtyMonths(of marks: [DirtyWalletMonth]) -> Set<WalletMonth> {
        Set(marks.compactMap { WalletMonth($0.wallet, $0.month) }.filter { !$0.wallet.isDeleted })
    }

    /// The net of each of `months`, counted from its transactions outside Recently Deleted in `context`, its unsaved
    /// changes included. One fetch per wallet for each stretch of its months less than a year apart: a wallet moved to
    /// Recently Deleted, which marks every month it held, is one read rather than one a month, and a date moved across
    /// years two small ones rather than every month between.
    private static func count(_ months: Set<WalletMonth>, in context: ModelContext) throws -> [WalletMonth: Int] {
        var net = Dictionary(uniqueKeysWithValues: months.map { ($0, 0) })
        for walletMonths in Dictionary(grouping: months, by: { ObjectIdentifier($0.wallet) }).values {
            guard let wallet = walletMonths.first?.wallet else { continue }
            for stretch in stretches(of: walletMonths.map(\.month)) {
                for transaction in try context.fetch(counted(in: wallet, during: stretch)) where !transaction.isDeleted {
                    net[WalletMonth(wallet: wallet, month: CalendarMonth(transaction.day))]? += transaction.netCents
                }
            }
        }
        return net
    }

    /// `months` in order, cut wherever the next is a year or more after the one before.
    private static func stretches(of months: [CalendarMonth]) -> [ClosedRange<CalendarMonth>] {
        var stretches: [ClosedRange<CalendarMonth>] = []
        for month in months.sorted() {
            if let last = stretches.last, month < last.upperBound.adding(months: 12) {
                stretches[stretches.count - 1] = last.lowerBound...month
            } else {
                stretches.append(month...month)
            }
        }
        return stretches
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

    /// Makes `netCents` the saved total of `month`. A month that nets to nothing and had no total yet gets none.
    private static func save(_ netCents: Int, as month: WalletMonth, in context: ModelContext) {
        if let total = (month.wallet.monthTotals ?? []).first(where: { !$0.isDeleted && $0.month == month.month }) {
            if total.netCents != netCents { total.netCents = netCents }
        } else if netCents != 0 {
            WalletMonthTotal.insert(netCents, for: month.month, of: month.wallet, in: context)
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
            WalletMonthTotal.insert(netCents, for: month.month, of: month.wallet, in: context)
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
        let month: CalendarMonth

        init(wallet: Wallet, month: CalendarMonth) {
            self.wallet = wallet
            self.month = month
        }

        /// `month` of `wallet`, or `nil` for what is in no wallet.
        init?(_ wallet: Wallet?, _ month: CalendarMonth) {
            guard let wallet else { return nil }
            self.init(wallet: wallet, month: month)
        }

        static func == (lhs: WalletMonth, rhs: WalletMonth) -> Bool {
            lhs.wallet === rhs.wallet && lhs.month == rhs.month
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(wallet))
            hasher.combine(month)
        }
    }

    /// The net of each wallet-month, counted from every transaction in `context` outside Recently Deleted, its unsaved
    /// changes included: what the saved totals should hold. One pass over every transaction.
    private static func fullCount(in context: ModelContext) throws -> [WalletMonth: Int] {
        var net: [WalletMonth: Int] = [:]
        for transaction in try context.fetch(Transaction.notDeleted) where !transaction.isDeleted {
            guard let wallet = transaction.wallet, !wallet.isDeleted else { continue }
            net[WalletMonth(wallet: wallet, month: CalendarMonth(transaction.day)), default: 0] += transaction.netCents
        }
        return net
    }

    // MARK: Checking

    /// A wallet-month whose saved total isn't what its transactions add up to.
    struct Mismatch {
        let walletMonth: WalletMonth
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
            saved[WalletMonth(wallet: wallet, month: total.month), default: 0] += total.netCents
        }
        var dirty: Set<WalletMonth> = []
        for mark in try context.fetch(FetchDescriptor<DirtyWalletMonth>()) where !mark.isDeleted {
            if let month = WalletMonth(mark.wallet, mark.month) { dirty.insert(month) }
        }
        return Set(counted.keys).union(saved.keys).subtracting(dirty).compactMap { month in
            let savedCents = saved[month] ?? 0
            let countedCents = counted[month] ?? 0
            guard savedCents != countedCents else { return nil }
            return Mismatch(walletMonth: month, savedCents: savedCents, countedCents: countedCents)
        }
        .sorted {
            ($0.walletMonth.wallet.name, $0.walletMonth.month) < ($1.walletMonth.wallet.name, $1.walletMonth.month)
        }
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
            if let walletMonth = WalletMonth(total.wallet, total.month) { net[walletMonth, default: 0] += total.netCents }
        }
        let marks = try context.fetch(FetchDescriptor<DirtyWalletMonth>()).filter { !$0.isDeleted }
        let dirty = dirtyMonths(of: marks).filter { $0.month <= month }
        if !dirty.isEmpty {
            net.merge(try count(dirty, in: context)) { $1 }
        }
        return net
    }
}
