import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The saved month totals: for each wallet and calendar month, the net of that month's transactions outside Recently
/// Deleted, counted again in each save that changed one, rebuilt when their format changes or an import
/// replaces everything, and gone with their wallet (ADR-0013).
@MainActor
@Suite(.namedInTheLog)
struct WalletMonthTotalTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }

    init() throws {
        store = try TestStore()
    }

    private func draft(_ cents: Int, on day: CalendarDay, in wallet: Wallet? = nil) throws -> TransactionDraft {
        var draft = TransactionDraft(type: .expense, day: day)
        draft.wallet = wallet ?? checking
        draft.entry = AmountEntry(cents: cents)
        draft.category = try store.category("Restaurants")
        return draft
    }

    // MARK: Counted in each save

    @Test func savingATransactionCountsItsMonth() throws {
        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try Transaction.create(draft(12_50, on: day(2026, 10, 20)), in: context)

        #expect(try totals(in: context) == ["Checking 2026-10: -4250"])
        #expect(try context.fetchCount(FetchDescriptor<DirtyWalletMonth>()) == 0)
    }

    @Test func everyMonthIsSavedTheSameWayTheFutureOnesToo() throws {
        try Transaction.create(draft(30_00, on: day(2026, 9, 5)), in: context)
        try Transaction.create(draft(10_00, on: TestStore.today), in: context)
        try Transaction.create(draft(5_00, on: day(2026, 10, 30)), in: context)
        try Transaction.create(draft(7_00, on: day(2027, 1, 2)), in: context)

        #expect(try totals(in: context) == [
            "Checking 2026-09: -3000", "Checking 2026-10: -1500", "Checking 2027-01: -700",
        ])
    }

    @Test func movingATransactionToAnotherMonthAndWalletCountsWhereItLeftAndWhereItWent() throws {
        let savings = context.addWallet("Savings")
        try Transaction.create(draft(12_00, on: day(2026, 3, 20)), in: context)
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 3, 14)), in: context)

        var edit = TransactionDraft(editing: dinner)
        edit.day = day(2026, 5, 2)
        edit.wallet = savings
        try dinner.update(with: edit)

        #expect(try totals(in: context) == ["Checking 2026-03: -1200", "Savings 2026-05: -3000"])
    }

    @Test func aReimbursementCountsInTheMonthOfItsExpense() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 9, 25)), in: context)

        try context.payBack(10_00, on: day(2026, 10, 2), to: dinner)

        #expect(try totals(in: context) == ["Checking 2026-09: -2000"])
    }

    @Test func aTransactionInRecentlyDeletedCountsInNoTotal() throws {
        try Transaction.create(draft(12_00, on: day(2026, 10, 1)), in: context)
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)

        try dinner.delete(.onlySelected)
        #expect(try totals(in: context) == ["Checking 2026-10: -1200"])

        try dinner.restore()
        #expect(try totals(in: context) == ["Checking 2026-10: -4200"])
    }

    @Test func monthsYearsApartInOneWalletAreEachCountedAndNoneBetween() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2020, 3, 14)), in: context)
        try Transaction.create(draft(5_00, on: day(2023, 6, 1)), in: context)
        try Transaction.create(draft(2_00, on: day(2026, 9, 30)), in: context)

        var edit = TransactionDraft(editing: dinner)
        edit.day = day(2026, 10, 2)
        try dinner.update(with: edit)

        #expect(try totals(in: context) == [
            "Checking 2023-06: -500", "Checking 2026-09: -200", "Checking 2026-10: -3000",
        ])
    }

    @Test func aMonthChangedAgainAfterItWasCountedIsCountedAgain() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)

        for cents in [31_00, 32_00] {
            var edit = TransactionDraft(editing: dinner)
            edit.entry = AmountEntry(cents: cents)
            try dinner.update(with: edit)
        }

        #expect(try totals(in: context) == ["Checking 2026-10: -3200"])
    }

    /// So every other observer of the store's saves (``StoreSaves``, ``NotDeletedTransactions``) sees each save once,
    /// never one saved inside another.
    @Test func aChangeAndTheTotalsItMovesGoIntoOneSave() throws {
        let saves = SaveCount(context)

        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)

        #expect(saves.count == 1)
        #expect(!context.hasChanges)
        #expect(try totals(in: context) == ["Checking 2026-10: -3000"])
    }

    @Test func theTotalsASaveCountedAreInTheStoreWhenItOpensAgain() throws {
        let url = URL.temporaryDirectory
            .appending(path: "GroshTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Grosh.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let first = try GroshStore.makeContainer(at: url)
            try StoreOpening.prepare(first.mainContext)
            first.mainContext.record(-12_00, on: day(2026, 10, 3), in: first.mainContext.addWallet("Cash"))
            try first.mainContext.save()
        }

        let reopened = TestStore.checked(try GroshStore.makeContainer(at: url))

        #expect(try totals(in: reopened.mainContext) == ["Cash 2026-10: -1200"])
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<DirtyWalletMonth>()) == 0)
    }

    // MARK: Rebuilt

    @Test func openingAStoreSavedBeforeThereWereTotalsBuildsThem() throws {
        // Saved as the app did before it kept totals: none, no marks and no format version.
        let container = try TestStore.makeContainer(countingEachSave: false)
        let other = container.mainContext
        let cash = other.addWallet("Cash")
        other.record(-12_00, on: day(2026, 10, 3), in: cash)
        other.record(-8_00, on: day(2026, 9, 3), in: cash)
        try other.save()
        for mark in try other.fetch(FetchDescriptor<DirtyWalletMonth>()) {
            other.delete(mark)
        }
        try other.save()

        try StoreOpening.prepare(other)

        #expect(try totals(in: other) == ["Cash 2026-09: -800", "Cash 2026-10: -1200"])
    }

    @Test func openingAStoreWhoseTotalsAreOfAnOlderFormatBuildsThemAgain() throws {
        try StoreOpening.prepare(context)
        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        // What an older format counted differently.
        let total = try #require(try context.fetch(FetchDescriptor<WalletMonthTotal>()).first)
        total.netCents = 1
        let format = try #require(try context.fetch(FetchDescriptor<WalletMonthTotalFormat>()).first)
        format.version = WalletMonthTotals.formatVersion - 1
        try context.save()

        try StoreOpening.prepare(context)

        #expect(try totals(in: context) == ["Checking 2026-10: -3000"])
        #expect(try context.fetch(FetchDescriptor<WalletMonthTotalFormat>()).map(\.version) == [
            WalletMonthTotals.formatVersion
        ])
    }

    /// So the first screen to read a balance never saves while it draws.
    @Test func openingAStoreWithAMonthStillDirtyCountsIt() throws {
        // Saved where nothing counts the totals after a save, as when the app stopped between a save and its count.
        let container = try TestStore.makeContainer(countingEachSave: false)
        let other = container.mainContext
        try CategorySeeder.seedIfNeeded(in: other)
        let cash = other.addWallet("Cash")
        try WalletMonthTotals.rebuild(in: other)
        try other.save()
        other.record(-12_00, on: day(2026, 10, 3), in: cash)
        try other.save()

        try StoreOpening.prepare(other)

        #expect(try totals(in: other) == ["Cash 2026-10: -1200"])
        #expect(try other.fetchCount(FetchDescriptor<DirtyWalletMonth>()) == 0)
    }

    // MARK: Wallets and imports

    @Test func removingAWalletForGoodRemovesItsTotals() throws {
        let savings = context.addWallet("Savings")
        try Transaction.create(draft(30_00, on: day(2026, 10, 5), in: savings), in: context)
        try Transaction.create(draft(12_00, on: day(2026, 9, 5), in: savings), in: context)
        try Transaction.create(draft(5_00, on: day(2026, 10, 5)), in: context)
        try savings.delete(today: TestStore.today)
        #expect(try context.fetchCount(FetchDescriptor<WalletMonthTotal>()) == 3)

        try RecentlyDeleted.empty(in: context)

        #expect(try context.fetch(FetchDescriptor<WalletMonthTotal>()).map { $0.wallet?.name } == ["Checking"])
    }

    @Test func anImportBuildsEveryTotalAgainInItsOneSave() throws {
        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        let saves = SaveCount(context)

        try context.importMoneyLover(moneyLoverExport(
            "1,10/05/2026,Café,-10.91,USD,Cash,Coffee,,,,",
            "2,09/20/2026,Café,-4.00,USD,Cash,,,,,",
            "3,10/06/2026,Salary,100.00,USD,Bank,,,,,"
        ))

        #expect(try totals(in: context) == ["Cash 2026-09: -400", "Cash 2026-10: -1091", "Bank 2026-10: 10000"])
        #expect(try context.fetchCount(FetchDescriptor<DirtyWalletMonth>()) == 0)
        #expect(saves.count == 1)
    }

    // MARK: Checked against a full count

    @Test func aTotalThatDiffersFromItsTransactionsIsFound() throws {
        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try Transaction.create(draft(8_00, on: day(2026, 9, 5)), in: context)
        let october = try #require(
            try context.fetch(FetchDescriptor<WalletMonthTotal>()).first { $0.month == CalendarMonth(year: 2026, month: 10) }
        )
        october.netCents = -1
        try context.save()

        let found = try WalletMonthTotals.mismatches(in: context).map { mismatch in
            return "\(mismatch.wallet.name) \(mismatch.month.numericTitle): saved \(mismatch.savedCents), "
                + "counted \(mismatch.countedCents)"
        }

        #expect(found == ["Checking 10/2026: saved -1, counted -3000"])
        // Right again, for the check every test's store ends with.
        try WalletMonthTotals.rebuild(in: context)
        try context.save()
    }

    @Test func aMonthWaitingToBeCountedIsNoMismatch() throws {
        let container = try TestStore.makeContainer(countingEachSave: false)
        let other = container.mainContext
        other.record(-12_00, on: day(2026, 10, 3), in: other.addWallet("Cash"))
        try other.save()

        #expect(try WalletMonthTotals.mismatches(in: other).isEmpty)
    }

    // MARK: Read

    /// A screen reads the totals while it draws, when nothing may save.
    @Test func aMonthStillDirtyWhenTheTotalsAreReadIsCountedThenWithoutSaving() throws {
        // Saved where nothing counts the totals after a save, as when the app stopped between a save and its count.
        let container = try TestStore.makeContainer(countingEachSave: false)
        let other = container.mainContext
        let cash = other.addWallet("Cash")
        other.record(-12_00, on: day(2026, 10, 3), in: cash)
        other.record(-8_00, on: day(2026, 9, 3), in: cash)
        try other.save()
        let saves = SaveCount(other)

        let read = try WalletMonthTotals.read(through: CalendarMonth(year: 2026, month: 10), in: other)

        #expect(try describe(read, in: other) == ["Cash 2026-09: -800", "Cash 2026-10: -1200"])
        #expect(saves.count == 0)
        #expect(!other.hasChanges)
    }

    @Test func aMonthLeftDirtyIsCountedByTheNextSave() throws {
        // Saved by a context whose saves nothing counts, as a save off the main thread is.
        let elsewhere = ModelContext(store.container)
        let cash = elsewhere.addWallet("Cash")
        elsewhere.record(-12_00, on: day(2026, 10, 3), in: cash)
        try elsewhere.save()

        try Transaction.create(draft(30_00, on: day(2026, 9, 5)), in: context)

        #expect(try totals(in: context) == ["Cash 2026-10: -1200", "Checking 2026-09: -3000"])
        #expect(try context.fetchCount(FetchDescriptor<DirtyWalletMonth>()) == 0)
    }

    @Test func readingStopsAtTheMonthAskedFor() throws {
        try Transaction.create(draft(30_00, on: day(2026, 9, 5)), in: context)
        try Transaction.create(draft(10_00, on: day(2026, 10, 5)), in: context)
        try Transaction.create(draft(7_00, on: day(2026, 11, 2)), in: context)

        let read = try WalletMonthTotals.read(through: CalendarMonth(year: 2026, month: 10), in: context)

        #expect(try describe(read, in: context) == ["Checking 2026-09: -3000", "Checking 2026-10: -1000"])
    }
}

/// Every saved month total in `context`, as "<wallet> <yyyy>-<mm>: <net cents>", leaving out the months that net to
/// nothing.
@MainActor
func totals(in context: ModelContext) throws -> Set<String> {
    Set(try context.fetch(FetchDescriptor<WalletMonthTotal>()).filter { $0.netCents != 0 }.map(describe))
}

/// How many times a context has saved since this began counting.
@MainActor
final class SaveCount {
    private(set) var count = 0
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    init(_ context: ModelContext) {
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }
}

@MainActor
private func describe(_ total: WalletMonthTotal) -> String {
    describe(total.wallet, total.month, total.netCents)
}

/// The nets ``WalletMonthTotals/read(through:in:)`` gave, as ``totals(in:)`` writes them.
@MainActor
private func describe(_ read: [WalletMonthTotals.WalletMonth: Int], in context: ModelContext) throws -> Set<String> {
    let wallets = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Wallet>()).map { (ObjectIdentifier($0), $0) })
    return Set(read.map { describe(wallets[$0.key.wallet], $0.key.month, $0.value) })
}

@MainActor
private func describe(_ wallet: Wallet?, _ month: CalendarMonth, _ netCents: Int) -> String {
    String(format: "%@ %04d-%02d: %d", wallet?.name ?? "-", month.year, month.month, netCents)
}
