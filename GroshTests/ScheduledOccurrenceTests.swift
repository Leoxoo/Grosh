import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Scheduled rows: the occurrences Future lists for a Recurring transaction that are still to come, the wallets they
/// show for, and that they add to no day's total.
@MainActor
struct ScheduledOccurrenceTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    /// The day the rows are listed on: occurrences dated on or before it are transactions already, or were skipped.
    private let today = CalendarDay(year: 2026, month: 10, day: 11)

    init() throws {
        store = try CategoryFixture()
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    /// A Recurring transaction of 15.99 starting on `start`, paid from the fixture's wallet unless `wallet` is given,
    /// and saved on `today`.
    private func makeSchedule(
        starting start: CalendarDay, preset: RepeatPreset = .monthly, wallet: Wallet? = nil
    ) throws -> RecurringTransaction {
        let category = Grosh.Category(name: "Subscriptions", type: .expense, symbolName: "repeat", color: .purple)
        context.insert(category)
        var draft = RecurringDraft(startDay: start)
        draft.name = "Netflix"
        draft.amount = Money(cents: 1599)
        draft.wallet = wallet ?? store.wallet
        draft.category = category
        draft.preset = preset
        return try RecurringTransaction.create(draft, today: today, in: context)
    }

    @Test func theNextTwelveOccurrencesAfterTodayAreListed() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)

        #expect(recurring.scheduledDays(today: today) == (12...23).map { day(2026, 10, $0) })
    }

    @Test func nothingBeyondOneYearAheadIsListed() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .yearly)

        #expect(recurring.scheduledDays(today: today) == [day(2026, 10, 12)])
    }

    @Test func occurrencesAlreadyMadeOrSkippedAreNotListed() throws {
        // Saved on October 11, so the October 1 occurrence was already due and is skipped rather than listed.
        let recurring = try makeSchedule(starting: day(2026, 10, 1))

        #expect(recurring.scheduledDays(today: today).first == day(2026, 11, 1))
        #expect(recurring.scheduledDays(today: today).count == 12)

        try RecurringTransaction.catchUp(through: day(2026, 11, 1), in: context)

        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 11, 1)])
        #expect(recurring.scheduledDays(today: day(2026, 11, 1)).first == day(2026, 12, 1))
    }

    @Test func aPausedOrRecentlyDeletedWalletListsNoScheduledRows() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        #expect(recurring.scheduledDays(today: today).count == 12)

        store.wallet.isArchived = true
        #expect(recurring.scheduledDays(today: today).isEmpty)

        store.wallet.isArchived = false
        store.wallet.deletedAt = Date.now
        #expect(recurring.scheduledDays(today: today).isEmpty)
    }

    @Test func aScheduleInRecentlyDeletedListsNoScheduledRows() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        #expect(recurring.scheduledDays(today: today).count == 12)

        try recurring.delete(today: today, in: context)
        #expect(recurring.scheduledDays(today: today).isEmpty)
    }

    @Test func theTotalListsOnlyTheWalletsCountedInIt() throws {
        let savings = Wallet(name: "Savings")
        savings.includeInTotal = false
        context.insert(savings)
        let checking = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly)
        let kept = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly, wallet: savings)
        let schedules = [checking, kept]

        let total = schedules.scheduledOccurrences(selection: .total, today: today)
        let inSavings = schedules.scheduledOccurrences(selection: .wallet(savings), today: today)

        #expect(total.count == 12)
        #expect(total.allSatisfy { $0.recurring == checking })
        #expect(inSavings.count == 12)
        #expect(inSavings.allSatisfy { $0.recurring == kept })
    }

    @Test func rowsListNewestDayFirst() throws {
        let daily = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        let weekly = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly)

        let days = [daily, weekly].scheduledOccurrences(selection: .total, today: today).map(\.day)

        #expect(days.first == day(2026, 12, 28))
        #expect(days == days.sorted(by: >))
    }

    @Test func aDayListsItsTransactionsThenItsScheduledRowsAndTotalsOnlyTheTransactions() throws {
        let netflix = try makeSchedule(starting: day(2026, 10, 20))
        let rows = [netflix].scheduledOccurrences(selection: .total, today: today)
        let lunch = Transaction(
            amount: Money(cents: -5_00), day: day(2026, 10, 20), wallet: store.wallet, category: nil
        )
        context.insert(lunch)

        let days = TransactionDay.days(of: [lunch], scheduled: rows)

        #expect(days.count == 12)
        #expect(days.first?.day == day(2027, 9, 20))
        #expect(days.filter { $0.transactions.isEmpty }.count == 11)
        let october = try #require(days.first { $0.day == day(2026, 10, 20) })
        #expect(october.transactions == [lunch])
        #expect(october.scheduled.map(\.day) == [day(2026, 10, 20)])
        #expect(october.net.cents == -5_00)
    }
}
