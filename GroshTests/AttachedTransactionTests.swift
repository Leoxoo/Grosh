import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Attaching existing transactions to a Recurring transaction and unlinking them: only the link changes, nothing is
/// deleted, and the schedule keeps its place.
@MainActor
@Suite(.namedInTheLog)
struct AttachedTransactionTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// A monthly Netflix of 15.99 starting on `start`, paid from the fixture's wallet.
    private func netflix(starting start: CalendarDay) throws -> RecurringTransaction {
        let category = Grosh.Category(name: "Subscriptions", type: .expense, symbolName: "repeat", color: .purple)
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

    /// A 4.99 spend on October 1 in `wallet`, filed under `category` and paid with `card` when one is given.
    private func spent(on category: Grosh.Category?, in wallet: Wallet, card: Card? = nil) -> Transaction {
        let transaction = Transaction(
            amount: Money(cents: -499), day: day(2026, 10, 1), wallet: wallet, category: category, card: card
        )
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

    @Test func attachingRefusesATransactionInRecentlyDeletedOrHeldByAnotherSchedule() throws {
        let recurring = try netflix(starting: day(2026, 10, 12))
        let other = try netflix(starting: day(2026, 10, 12))
        let deleted = entered(on: day(2026, 10, 1), cents: -500)
        deleted.deletedAt = .now
        let held = entered(on: day(2026, 10, 2), cents: -600)
        try other.attach(held, in: context)

        #expect(throws: AttachError.notAttachable) { try recurring.attach(deleted, in: context) }
        #expect(throws: AttachError.notAttachable) { try recurring.attach(held, in: context) }

        #expect(deleted.recurring == nil)
        #expect(held.recurring == other)
        #expect(recurring.attachedTransactions.isEmpty)
        #expect(other.attachedTransactions == [held])
    }

    @Test func thePickerOpensNarrowedToTheSchedulesWalletAndCategoryButNotItsCard() throws {
        let apps = Grosh.Category(name: "Apps", type: .expense, symbolName: "app", color: .purple)
        let groceries = Grosh.Category(name: "Groceries", type: .expense, symbolName: "cart", color: .purple)
        let chase = Card(name: "Chase", kind: .credit, payingWallet: store.wallet)
        let savings = Wallet(name: "Savings")
        context.insert(apps)
        context.insert(groceries)
        context.insert(chase)
        context.insert(savings)
        var draft = RecurringDraft(startDay: day(2026, 10, 12))
        draft.name = "App subscription"
        draft.amount = Money(cents: 499)
        draft.wallet = store.wallet
        draft.category = apps
        draft.card = chase
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        let filter = recurring.linkPickerFilter
        #expect(filter.wallet?.persistentModelID == store.wallet.persistentModelID)
        #expect(filter.category?.persistentModelID == apps.persistentModelID)
        #expect(filter.card == nil)

        let plain = spent(on: apps, in: store.wallet)
        let paidWithChase = spent(on: apps, in: store.wallet, card: chase)
        let otherCategory = spent(on: groceries, in: store.wallet)
        let otherWallet = spent(on: apps, in: savings)
        let transactions = [plain, paidWithChase, otherCategory, otherWallet]

        let listed = transactions.matching(filter).map(\.persistentModelID)
        #expect(listed == [plain, paidWithChase].map(\.persistentModelID))

        var cleared = filter
        cleared.clearFilters()
        #expect(transactions.matching(cleared).count == 4)
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
