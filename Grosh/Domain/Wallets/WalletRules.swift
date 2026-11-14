import Foundation
import SwiftData

extension Wallet {
    /// The order the user set by dragging. Every list and picker of wallets uses it.
    static let userOrder: [SortDescriptor<Wallet>] = [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]

    /// Unarchived wallets in the user's order: what Home and every wallet picker show. A wallet in Recently Deleted
    /// is left out.
    static var unarchived: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { !$0.isArchived && $0.deletedAt == nil }, sortBy: userOrder)
    }

    /// Archived wallets in the user's order, leaving out any in Recently Deleted.
    static var archived: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { $0.isArchived && $0.deletedAt == nil }, sortBy: userOrder)
    }

    /// Every wallet in the user's order, archived ones included, leaving out any in Recently Deleted.
    static var notDeleted: FetchDescriptor<Wallet> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: userOrder)
    }

    /// Applies a drag in `ordered` (a list in the user's order) by renumbering the wallets in their new order.
    /// Saves.
    static func move(_ ordered: [Wallet], fromOffsets source: IndexSet, toOffset destination: Int) throws {
        try ordered.move(fromOffsets: source, toOffset: destination, renumbering: \.sortOrder)
    }

    /// Retires the wallet: it leaves the Total and every picker, but keeps all of its transactions. Its Recurring
    /// transactions pause, after making what has fallen due by `today`, and make nothing until it is unarchived. Saves.
    @MainActor
    func archive(today: CalendarDay) throws {
        let context = try storeContext()
        for schedule in recurringTransactions ?? [] {
            try schedule.makeDueTransactions(through: today)
        }
        isArchived = true
        try context.save()
    }

    /// Brings an archived wallet back into its place in the user's order. Its Recurring transactions resume, and what
    /// fell due while it was archived is not made. Saves.
    @MainActor
    func unarchive(today: CalendarDay) throws {
        isArchived = false
        for schedule in recurringTransactions ?? [] where schedule.isActive {
            schedule.skipOccurrences(through: today)
        }
        try saveToStore()
    }

    /// Whether the wallet counts toward the Total: unarchived, marked "Include in total", and not in Recently Deleted.
    var countsInTotal: Bool { !isArchived && includeInTotal && deletedAt == nil }
}

/// The balance of every wallet on one day: every balance the app shows, a wallet's, the Total's or what Adjust Balance
/// calls the recorded balance, is read from it. A wallet's balance is the sum of its transactions dated that day or
/// earlier: those dated after belong to Future and don't count yet, and those in Recently Deleted never do.
///
/// Home, the Wallets list and the Wallet selector read it from the saved month totals (``read(asOf:in:)``, ADR-0013);
/// the other screens add it up in one pass over the transactions outside Recently Deleted that they already hold, as
/// ``NotDeletedTransactions`` keeps them.
nonisolated struct WalletBalances {
    private let centsByWallet: [ObjectIdentifier: Int]

    /// The balances on `today` of the wallets `transactions` belong to, from every transaction outside Recently
    /// Deleted: those dated today or earlier count.
    init(_ transactions: some Sequence<some DatedAmount>, asOf today: CalendarDay) {
        var centsByWallet: [ObjectIdentifier: Int] = [:]
        for transaction in transactions where transaction.dayRaw <= today.rawValue {
            guard let wallet = transaction.wallet else { continue }
            centsByWallet[ObjectIdentifier(wallet), default: 0] += transaction.netCents
        }
        self.centsByWallet = centsByWallet
    }

    /// The balances on a day from the saved month totals (ADR-0013): each wallet's `monthNets` through the day's month
    /// (``WalletMonthTotals/read(through:in:)``) added up, less what its `datedLaterThisMonth`
    /// (``datedLaterThisMonth(than:)``) add, as they don't count yet.
    @MainActor
    init(
        monthNets: [WalletMonthTotals.WalletMonth: Int], datedLaterThisMonth: some Sequence<some DatedAmount>
    ) {
        var centsByWallet: [ObjectIdentifier: Int] = [:]
        for (month, netCents) in monthNets {
            centsByWallet[month.wallet, default: 0] += netCents
        }
        for transaction in datedLaterThisMonth {
            guard let wallet = transaction.wallet else { continue }
            centsByWallet[ObjectIdentifier(wallet), default: 0] -= transaction.netCents
        }
        self.centsByWallet = centsByWallet
    }

    /// The transactions of `today`'s month dated after it, outside Recently Deleted: counted in the month's saved total,
    /// they don't count in a balance yet. Usually a handful.
    static func datedLaterThisMonth(than today: CalendarDay) -> FetchDescriptor<Transaction> {
        let after = today.rawValue
        let last = CalendarMonth(today).lastDay.rawValue
        return FetchDescriptor(predicate: #Predicate {
            $0.dayRaw > after && $0.dayRaw <= last && $0.deletedAt == nil
        })
    }

    /// Every wallet's balance on `today`, from the saved month totals through its month, any month still dirty counted
    /// in memory (``WalletMonthTotals/read(through:in:)``), less this month's transactions dated after it. A few small
    /// reads, never every transaction, and never a save.
    @MainActor
    static func read(asOf today: CalendarDay, in context: ModelContext) throws -> WalletBalances {
        WalletBalances(
            monthNets: try WalletMonthTotals.read(through: CalendarMonth(today), in: context),
            datedLaterThisMonth: try context.fetch(datedLaterThisMonth(than: today))
        )
    }

    /// Every wallet's balance on `today`, from the saved month totals (`fromSavedTotals`, ``read(asOf:in:)``) or, when
    /// they can't be read, counted from every transaction outside Recently Deleted: slow, but never a wrong $0. Logs
    /// what failed.
    @MainActor
    static func readOrCount(
        asOf today: CalendarDay, in context: ModelContext,
        fromSavedTotals: @MainActor (CalendarDay, ModelContext) throws -> WalletBalances = read(asOf:in:)
    ) -> WalletBalances {
        Log.store.attempt("Reading the wallets' balances") { try fromSavedTotals(today, context) }
            ?? Log.store.attempt("Counting the wallets' balances from every transaction") {
                WalletBalances(try context.fetch(Transaction.notDeleted), asOf: today)
            }
            ?? WalletBalances([LedgerEntry](), asOf: today)
    }

    /// The wallet's balance, in its own currency.
    func balance(of wallet: Wallet) -> Money {
        Money(cents: centsByWallet[ObjectIdentifier(wallet)] ?? 0, currencyCode: wallet.currencyCode)
    }

    /// The Total of `wallets`: the balances of those that count in it (``Wallet/countsInTotal``), added up per
    /// currency as ``Swift/Sequence/totalsPerCurrency`` adds them, a currency never added to another. With nothing to
    /// add up, or everything adding up to nothing, it is nothing in the currency of the first wallet in the Total.
    func total(of wallets: [Wallet]) -> [Money] {
        let totals = wallets.filter(\.countsInTotal).map(balance(of:)).totalsPerCurrency
        guard totals.isEmpty else { return totals }
        return [Money(cents: 0, currencyCode: WalletSelection.total.currencyCode(among: wallets))]
    }

    /// The balance of `selection`: the Total of `wallets`, or the one wallet's balance.
    func balance(of selection: WalletSelection, wallets: [Wallet]) -> [Money] {
        switch selection {
        case .total: total(of: wallets)
        case .wallet(let wallet): [balance(of: wallet)]
        }
    }
}
