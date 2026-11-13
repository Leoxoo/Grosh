import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Attaching existing transactions to a Recurring transaction and unlinking them: only the link changes, nothing is
/// deleted, and the schedule keeps its place.
@MainActor
@Suite(.namedInTheLog)
struct AttachedTransactionTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    /// A transaction entered by hand on `day` in Checking, with no category.
    private func entered(on day: CalendarDay, cents: Int) -> Transaction {
        context.record(cents, on: day, in: store.checking)
    }

    /// A 4.99 spend on October 1 in `wallet`, filed under `category` and paid with `card` when one is given.
    private func spent(on category: Grosh.Category?, in wallet: Wallet, card: Card? = nil) -> Transaction {
        context.record(-4_99, on: day(2026, 10, 1), in: wallet, under: category, card: card)
    }

    @Test func anAttachedTransactionIsListedAlongsideTheOnesTheScheduleMadeNewestFirst() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        let older = entered(on: day(2026, 9, 20), cents: -499)
        let newer = entered(on: day(2026, 10, 15), cents: -1000)

        try recurring.attach(older)
        try recurring.attach(newer)

        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 10, 15), day(2026, 10, 12), day(2026, 9, 20)])
        #expect(older.recurring == recurring)
    }

    @Test func attachingNeverMovesTheScheduleOrMakesAnOccurrence() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))

        try recurring.attach(entered(on: day(2026, 10, 1), cents: -1599))

        #expect(recurring.nextDueDay == day(2026, 10, 12))
        #expect(recurring.attachedTransactions.count == 1)
    }

    @Test func unlinkingDetachesATransactionWithoutDeletingIt() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction)

        try recurring.unlink(transaction)

        #expect(recurring.attachedTransactions.isEmpty)
        #expect(transaction.recurring == nil)
        #expect(transaction.deletedAt == nil)
        #expect(transaction.isAttachable)
        let stored = try context.fetch(FetchDescriptor<Transaction>())
        #expect(stored.contains(transaction))
    }

    @Test func unlinkingATransactionTheScheduleMadeKeepsItInItsWallet() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        let made = try #require(recurring.attachedTransactions.first)

        try recurring.unlink(made)

        #expect(recurring.attachedTransactions.isEmpty)
        #expect(made.wallet == store.checking)
        #expect(made.amountCents == -1599)
        #expect(recurring.nextDueDay == day(2026, 11, 12))
    }

    @Test func unlinkingLeavesATransactionHeldByAnotherScheduleAlone() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        let other = try store.netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try other.attach(transaction)

        try recurring.unlink(transaction)

        #expect(transaction.recurring == other)
        #expect(other.attachedTransactions == [transaction])
    }

    @Test func aTransactionInRecentlyDeletedLeavesTheListAndReturnsOnRestore() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction)

        transaction.deletedAt = .now
        #expect(recurring.attachedTransactions.isEmpty)
        #expect(!transaction.isAttachable)

        try transaction.restore()
        #expect(recurring.attachedTransactions == [transaction])
        #expect(transaction.recurring == recurring)
    }

    @Test func onlyATransactionNoScheduleHoldsAndOutsideRecentlyDeletedIsAttachable() throws {
        let schedule = try store.netflix(starting: day(2026, 10, 12))
        let free = entered(on: day(2026, 10, 1), cents: -500)
        let held = entered(on: day(2026, 10, 2), cents: -600)
        let deleted = entered(on: day(2026, 10, 3), cents: -700)
        try schedule.attach(held)
        deleted.deletedAt = .now

        #expect(free.isAttachable)
        #expect(!held.isAttachable)
        #expect(!deleted.isAttachable)
    }

    @Test func attachingRefusesATransactionInRecentlyDeletedOrHeldByAnotherSchedule() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        let other = try store.netflix(starting: day(2026, 10, 12))
        let deleted = entered(on: day(2026, 10, 1), cents: -500)
        deleted.deletedAt = .now
        let held = entered(on: day(2026, 10, 2), cents: -600)
        try other.attach(held)

        #expect(throws: AttachError.notAttachable) { try recurring.attach(deleted) }
        #expect(throws: AttachError.notAttachable) { try recurring.attach(held) }

        #expect(deleted.recurring == nil)
        #expect(held.recurring == other)
        #expect(recurring.attachedTransactions.isEmpty)
        #expect(other.attachedTransactions == [held])
    }

    @Test func thePickerOpensNarrowedToTheSchedulesWalletAndCategoryButNotItsCard() throws {
        let apps = context.addCategory("Apps")
        let groceries = context.addCategory("Groceries")
        let chase = try context.addCard("Chase", paidFrom: store.checking)
        let savings = context.addWallet("Savings")
        var draft = store.recurringDraft("App subscription", 4_99, under: apps, starting: day(2026, 10, 12))
        draft.card = chase
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        let filter = recurring.linkPickerFilter
        #expect(filter.wallet?.persistentModelID == store.checking.persistentModelID)
        #expect(filter.category?.persistentModelID == apps.persistentModelID)
        #expect(filter.card == nil)

        let plain = spent(on: apps, in: store.checking)
        let paidWithChase = spent(on: apps, in: store.checking, card: chase)
        let otherCategory = spent(on: groceries, in: store.checking)
        let otherWallet = spent(on: apps, in: savings)
        let transactions = [plain, paidWithChase, otherCategory, otherWallet]

        let listed = transactions.matching(filter).map(\.persistentModelID)
        #expect(listed == [plain, paidWithChase].map(\.persistentModelID))

        var cleared = filter
        cleared.clearFilters()
        #expect(transactions.matching(cleared).count == 4)
    }

    @Test func deletingTheScheduleLeavesItsAttachedTransactionsAsOrdinaryOnes() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction)

        try recurring.delete(today: today)

        #expect(transaction.recurring == nil)
        #expect(transaction.isAttachable)
    }
}
