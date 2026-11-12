import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Scheduled rows: the occurrences Future lists for a Recurring transaction that are still to come, the wallets they
/// show for, and that they add to no day's total.
@MainActor
@Suite(.namedInTheLog)
struct ScheduledOccurrenceTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    /// The day the rows are listed on: occurrences dated on or before it are transactions already, or were skipped.
    private let today = CalendarDay(year: 2026, month: 10, day: 11)

    init() throws {
        store = try TestStore()
    }

    /// The fixture's Netflix starting on `start`, paid from Checking unless `wallet` is given,
    /// repeating `preset` until `end`, and saved on `today`.
    private func makeSchedule(
        starting start: CalendarDay, preset: RepeatPreset = .monthly, wallet: Wallet? = nil, end: RepeatEnd = .forever
    ) throws -> RecurringTransaction {
        try store.netflix(starting: start, today: today, preset: preset, wallet: wallet, end: end)
    }

    @Test func aScheduleThatRepeatsForeverListsOnlyItsNextOccurrence() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)

        #expect(recurring.scheduledDays(today: today) == [day(2026, 10, 12)])
    }

    @Test func aScheduleEndingAfterACountListsEveryPaymentStillToCome() throws {
        // Fifteen monthly payments from October 12 run on to December 12 of the following year: past twelve rows, and
        // past the year Future used to stop at.
        let recurring = try makeSchedule(starting: day(2026, 10, 12), end: .afterCount(15))

        let days = recurring.scheduledDays(today: today)
        #expect(days.count == 15)
        #expect(days.last == day(2027, 12, 12))
    }

    @Test func aScheduleEndingOnADateListsEveryOccurrenceUpToThatDay() throws {
        // Monthly on the 12th from October 2026 to December 12, 2028: 27 payments, the last on the end day.
        let recurring = try makeSchedule(starting: day(2026, 10, 12), end: .until(day(2028, 12, 12)))

        let days = recurring.scheduledDays(today: today)
        #expect(days.count == 27)
        #expect(days.last == day(2028, 12, 12))
    }

    @Test func occurrencesAlreadyMadeOrSkippedAreNotListed() throws {
        // Saved on October 11, so the October 1 occurrence was already due and is skipped rather than listed.
        let recurring = try makeSchedule(starting: day(2026, 10, 1))

        #expect(recurring.scheduledDays(today: today) == [day(2026, 11, 1)])

        try RecurringTransaction.catchUp(through: day(2026, 11, 1), in: context)

        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 11, 1)])
        #expect(recurring.scheduledDays(today: day(2026, 11, 1)) == [day(2026, 12, 1)])
    }

    @Test func aScheduleEndingAfterACountSkipsPaymentsAlreadyMadeOrSkipped() throws {
        // Five payments from October 1: October's is skipped when the schedule is saved on October 11.
        let recurring = try makeSchedule(starting: day(2026, 10, 1), end: .afterCount(5))

        #expect(recurring.scheduledDays(today: today) == [
            day(2026, 11, 1), day(2026, 12, 1), day(2027, 1, 1), day(2027, 2, 1),
        ])

        try RecurringTransaction.catchUp(through: day(2026, 12, 1), in: context)

        #expect(recurring.scheduledDays(today: day(2026, 12, 1)) == [day(2027, 1, 1), day(2027, 2, 1)])
    }

    @Test func aScheduleThatHasEndedListsNothing() throws {
        // Two payments from October 1: October's is skipped when the schedule is saved, November's is still to come.
        let recurring = try makeSchedule(starting: day(2026, 10, 1), end: .afterCount(2))

        #expect(recurring.scheduledDays(today: today) == [day(2026, 11, 1)])
        #expect(recurring.scheduledDays(today: day(2026, 11, 2)).isEmpty)
    }

    @Test func aPausedOrRecentlyDeletedWalletListsNoScheduledRows() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        #expect(recurring.scheduledDays(today: today) == [day(2026, 10, 12)])

        store.checking.isArchived = true
        #expect(recurring.scheduledDays(today: today).isEmpty)

        store.checking.isArchived = false
        store.checking.deletedAt = Date.now
        #expect(recurring.scheduledDays(today: today).isEmpty)
    }

    @Test func aScheduleInRecentlyDeletedListsNoScheduledRows() throws {
        let recurring = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        #expect(recurring.scheduledDays(today: today) == [day(2026, 10, 12)])

        try recurring.delete(today: today)
        #expect(recurring.scheduledDays(today: today).isEmpty)
    }

    @Test func aBillWhoseAmountVariesHasEstimatedScheduledRowsAndOtherKindsDoNot() throws {
        var draft = store.recurringDraft(
            "Electricity", 25_00, under: context.addCategory("Utilities"), starting: day(2026, 10, 12)
        )
        draft.kind = .bill
        draft.amountVaries = true
        let electricity = try RecurringTransaction.create(draft, today: today, in: context)
        let netflix = try makeSchedule(starting: day(2026, 10, 12))

        let rows = [electricity, netflix].scheduledOccurrences(selection: .total, today: today)

        #expect(rows.filter { $0.recurring === electricity }.map(\.isEstimated) == [true])
        #expect(rows.filter { $0.recurring === netflix }.map(\.isEstimated) == [false])
    }

    @Test func aVaryingBillsScheduledRowsShowItsEstimateInPlaceOfItsAmount() throws {
        let water = context.addCategory("Water")
        for _ in 0..<2 {
            Transaction.insert(
                cents: -50_00, on: day(2026, 9, 1), wallet: store.checking, category: water, in: context
            )
        }
        try context.save()
        var draft = store.recurringDraft("Water", 0, under: water, starting: day(2026, 10, 12))
        draft.kind = .bill
        draft.amountVaries = true
        let bill = try RecurringTransaction.create(draft, today: today, in: context)

        let rows = [bill].scheduledOccurrences(selection: .total, today: today)

        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.amount.cents == -5_000 && $0.isEstimated })
    }

    @Test func theTotalListsOnlyTheWalletsCountedInIt() throws {
        let savings = context.addWallet("Savings", includeInTotal: false)
        let checking = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly)
        let kept = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly, wallet: savings)
        let schedules = [checking, kept]

        let total = schedules.scheduledOccurrences(selection: .total, today: today)
        let inSavings = schedules.scheduledOccurrences(selection: .wallet(savings), today: today)

        #expect(total.count == 1)
        #expect(total.allSatisfy { $0.recurring == checking })
        #expect(inSavings.count == 1)
        #expect(inSavings.allSatisfy { $0.recurring == kept })
    }

    @Test func rowsListNewestDayFirst() throws {
        let daily = try makeSchedule(starting: day(2026, 10, 12), preset: .daily, end: .afterCount(3))
        let weekly = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly, end: .afterCount(3))

        let days = [daily, weekly].scheduledOccurrences(selection: .total, today: today).map(\.day)

        #expect(days.first == day(2026, 10, 26))
        #expect(days == days.sorted(by: >))
    }

    @Test func aDayListsItsTransactionsThenItsScheduledRowsAndTotalsOnlyTheTransactions() throws {
        let netflix = try makeSchedule(starting: day(2026, 10, 20), end: .afterCount(3))
        let rows = [netflix].scheduledOccurrences(selection: .total, today: today)
        let lunch = Transaction.insert(
            cents: -5_00, on: day(2026, 10, 20), wallet: store.checking, category: nil, in: context
        )

        let days = TransactionDay.days(of: [lunch], scheduled: rows)

        #expect(days.count == 3)
        #expect(days.first?.day == day(2026, 12, 20))
        #expect(days.filter { $0.transactions.isEmpty }.count == 2)
        let october = try #require(days.first { $0.day == day(2026, 10, 20) })
        #expect(october.transactions == [lunch])
        #expect(october.scheduled.map(\.day) == [day(2026, 10, 20)])
        #expect(october.net.cents == -5_00)
    }

    @Test func futureListsTransactionsEnteredForAFutureDayAlongsideScheduledRows() throws {
        let netflix = try makeSchedule(starting: day(2026, 10, 20), end: .afterCount(3))
        let rows = [netflix].scheduledOccurrences(selection: .total, today: today)
        let dinner = Transaction.insert(
            cents: -40_00, on: day(2026, 11, 3), wallet: store.checking, category: nil, in: context
        )

        let future = Period.future.days(today: today)
        let shown = TransactionListing([dinner], showing: .total, on: future).transactions
        let days = TransactionDay.days(of: shown, scheduled: rows)

        #expect(shown == [dinner])
        #expect(days.map(\.day) == [day(2026, 12, 20), day(2026, 11, 20), day(2026, 11, 3), day(2026, 10, 20)])
        #expect(days.first { $0.day == day(2026, 11, 3) }?.transactions == [dinner])
    }
}
