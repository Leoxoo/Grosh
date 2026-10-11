import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Attaching existing transactions to a Recurring transaction and unlinking them: only the link changes, nothing is
/// deleted, and the schedule keeps its place.
@MainActor
struct AttachedTransactionTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    /// A monthly Netflix of 15.99 starting on `start`, paid from the fixture's wallet.
    private func netflix(starting start: CalendarDay) throws -> RecurringTransaction {
        let category = Category(name: "Subscriptions", type: .expense, symbolName: "repeat", color: .purple)
        context.insert(category)
        var draft = RecurringDraft(startDay: start)
        draft.name = "Netflix"
        draft.amount = Money(cents: 1599)
        draft.wallet = store.wallet
        draft.category = category
        return try RecurringTransaction.create(draft, today: today, in: context)
    }

    /// A transaction entered by hand on `day` in the fixture's wallet, with no category.
    private func entered(on day: CalendarDay, cents: Int) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: store.wallet, category: nil)
        context.insert(transaction)
        return transaction
    }

    @Test func anAttachedTransactionIsListedAlongsideTheOnesTheScheduleMadeNewestFirst() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        let older = entered(on: day(2026, 9, 20), cents: -499)
        let newer = entered(on: day(2026, 10, 15), cents: -1000)

        try recurring.attach(older, in: context)
        try recurring.attach(newer, in: context)

        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 10, 15), day(2026, 10, 12), day(2026, 9, 20)])
        #expect(older.recurring == recurring)
    }

    @Test func attachingNeverMovesTheScheduleOrMakesAnOccurrence() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))

        try recurring.attach(entered(on: day(2026, 10, 1), cents: -1599), in: context)

        #expect(recurring.nextDueDay == day(2026, 10, 12))
        #expect(recurring.handledThrough == nil)
        #expect(recurring.attachedTransactions.count == 1)
    }

    @Test func unlinkingDetachesATransactionWithoutDeletingIt() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction, in: context)

        try recurring.unlink(transaction, in: context)

        #expect(recurring.attachedTransactions.isEmpty)
        #expect(transaction.recurring == nil)
        #expect(transaction.deletedAt == nil)
        #expect(transaction.isAttachable)
        let stored = try context.fetch(FetchDescriptor<Transaction>())
        #expect(stored.contains(transaction))
    }

    @Test func unlinkingATransactionTheScheduleMadeKeepsItInItsWallet() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        let made = try #require(recurring.attachedTransactions.first)

        try recurring.unlink(made, in: context)

        #expect(recurring.attachedTransactions.isEmpty)
        #expect(made.wallet == store.wallet)
        #expect(made.amountCents == -1599)
        #expect(recurring.nextDueDay == day(2026, 11, 12))
    }

    @Test func unlinkingLeavesATransactionHeldByAnotherScheduleAlone() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        let other = try netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try other.attach(transaction, in: context)

        try recurring.unlink(transaction, in: context)

        #expect(transaction.recurring == other)
        #expect(other.attachedTransactions == [transaction])
    }

    @Test func aTransactionInRecentlyDeletedLeavesTheListAndReturnsOnRestore() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction, in: context)

        transaction.deletedAt = .now
        #expect(recurring.attachedTransactions.isEmpty)
        #expect(!transaction.isAttachable)

        try transaction.restore()
        #expect(recurring.attachedTransactions == [transaction])
        #expect(transaction.recurring == recurring)
    }

    @Test func onlyATransactionNoScheduleHoldsAndOutsideRecentlyDeletedIsAttachable() throws {
        let schedule = try netflix(starting: day(2026, 10, 12))
        let free = entered(on: day(2026, 10, 1), cents: -500)
        let held = entered(on: day(2026, 10, 2), cents: -600)
        let deleted = entered(on: day(2026, 10, 3), cents: -700)
        try schedule.attach(held, in: context)
        deleted.deletedAt = .now

        #expect(free.isAttachable)
        #expect(!held.isAttachable)
        #expect(!deleted.isAttachable)
    }

    @Test func deletingTheScheduleLeavesItsAttachedTransactionsAsOrdinaryOnes() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        let transaction = entered(on: day(2026, 10, 1), cents: -1599)
        try recurring.attach(transaction, in: context)

        try recurring.delete(today: today, in: context)

        #expect(transaction.recurring == nil)
        #expect(transaction.isAttachable)
    }
}
