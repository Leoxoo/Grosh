import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Recurring transactions with their wallet and in Recently Deleted: deleting one moves it to the bin and unlinks what
/// it made, restoring one skips what fell due meanwhile, and a deleted or paused schedule makes nothing.
@MainActor
@Suite(.namedInTheLog)
struct RecurringTransactionRecentlyDeletedTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = TestStore.today
    /// When things are deleted: October 13, the day after the October 12 occurrence.
    private let deletedAt = CalendarDay(year: 2026, month: 10, day: 13).date()

    init() throws {
        store = try TestStore()
    }

    // MARK: Deleting a schedule

    @Test func deletingAScheduleMovesItToRecentlyDeletedAndUnlinksWhatItMade() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        try recurring.delete(today: day(2026, 10, 12), at: deletedAt)

        #expect(recurring.isInRecentlyDeleted)
        #expect(try RecentlyDeleted(in: context).recurring == [recurring])
        #expect(recurring.attachedTransactions.isEmpty)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.map(\.amountCents) == [-1599])
        #expect(transactions.allSatisfy { $0.recurring == nil })
    }

    @Test func aDeletedScheduleMakesNothingAndIsNotActive() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try recurring.delete(today: today, at: deletedAt)

        try RecurringTransaction.catchUp(through: day(2026, 12, 31), in: context)

        #expect(!recurring.isActive)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    // MARK: Restoring a schedule

    @Test func restoringAScheduleKeepsItsSettingsAndDoesNotBackfill() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        try recurring.delete(today: day(2026, 10, 12), at: deletedAt)

        try recurring.restore(today: day(2026, 11, 20))

        #expect(!recurring.isInRecentlyDeleted)
        #expect(recurring.name == "Netflix")
        #expect(recurring.amountCents == 1599)
        #expect(recurring.wallet == store.checking)
        #expect(recurring.nextDueDay == day(2026, 12, 12))

        try RecurringTransaction.catchUp(through: day(2026, 11, 20), in: context)
        #expect(recurring.attachedTransactions.isEmpty)

        try RecurringTransaction.catchUp(through: day(2026, 12, 12), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 12, 12)])
    }

    @Test func aScheduleCannotBeRestoredWhileItsWalletIsInRecentlyDeleted() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try recurring.delete(today: today, at: deletedAt)
        try store.checking.delete(today: day(2026, 10, 14), at: day(2026, 10, 14).date())

        #expect(recurring.restoreBlocker == .walletIsDeleted)
        #expect(throws: RecentlyDeletedError.walletIsDeleted) { try recurring.restore(today: today) }
    }

    // MARK: Wallets

    @Test func aScheduleDeletedWithItsWalletComesBackOnlyWithIt() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        try store.checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        #expect(recurring.deletedWithWallet)
        #expect(recurring.restoreBlocker == .deletedWithWallet)
        #expect(throws: RecentlyDeletedError.deletedWithWallet) { try recurring.restore(today: today) }
        #expect(try RecentlyDeleted(in: context).recurring.isEmpty)
        #expect(store.checking.recurringDeletedWithIt == [recurring])

        try store.checking.restore(today: day(2026, 11, 20))

        #expect(!recurring.isInRecentlyDeleted)
        try RecurringTransaction.catchUp(through: day(2026, 12, 31), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 12, 12), day(2026, 10, 12)])
    }

    @Test func deletingAWalletMakesWhatFellDueFirstSoItGoesIntoItsItem() throws {
        _ = try store.netflix(starting: day(2026, 10, 12))

        try store.checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        #expect(store.checking.transactionsDeletedWithIt.map(\.day) == [day(2026, 10, 12)])
    }

    @Test func archivingAWalletPausesItsSchedulesAndUnarchivingDoesNotBackfill() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))

        try store.checking.archive(today: day(2026, 10, 12))

        #expect(recurring.isPaused)
        #expect(!recurring.isActive)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 10, 12)])

        try RecurringTransaction.catchUp(through: day(2026, 11, 20), in: context)
        #expect(recurring.attachedTransactions.count == 1)

        try store.checking.unarchive(today: day(2026, 11, 20))

        #expect(!recurring.isPaused)
        try RecurringTransaction.catchUp(through: day(2026, 11, 20), in: context)
        #expect(recurring.attachedTransactions.count == 1)

        try RecurringTransaction.catchUp(through: day(2026, 12, 12), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 12, 12), day(2026, 10, 12)])
    }

    // MARK: Removing for good

    @Test func purgingAnExpiredScheduleRemovesItForGoodAndKeepsWhatItMade() throws {
        let recurring = try store.netflix(starting: day(2026, 10, 12))
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        try recurring.delete(today: day(2026, 10, 12), at: deletedAt)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(29 * 86_400))
        #expect(try context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 1)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(30 * 86_400))
        #expect(try context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.recurring == nil)
    }

    @Test func deleteForeverAndEmptyingTheBinRemoveSchedulesForGood() throws {
        let gym = try store.netflix(starting: day(2026, 10, 12))
        let phone = try store.netflix(starting: day(2026, 10, 12))
        try gym.delete(today: today, at: deletedAt)
        try phone.delete(today: today, at: deletedAt)

        try gym.deleteForever()
        #expect(try context.fetch(FetchDescriptor<RecurringTransaction>()) == [phone])

        try RecentlyDeleted.empty(in: context)
        #expect(try context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
    }

    @Test func removingAWalletForGoodRemovesItsSchedules() throws {
        _ = try store.netflix(starting: day(2026, 10, 12))
        try store.checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        try store.checking.deleteForever()

        #expect(try context.fetchCount(FetchDescriptor<RecurringTransaction>()) == 0)
    }
}
