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

    @Test func aBillWhoseAmountVariesHasEstimatedScheduledRowsAndOtherKindsDoNot() throws {
        let utilities = Grosh.Category(name: "Utilities", type: .expense, symbolName: "bolt", color: .purple)
        context.insert(utilities)
        var draft = RecurringDraft(startDay: day(2026, 10, 12))
        draft.name = "Electricity"
        draft.amount = Money(cents: 2_500)
        draft.wallet = store.wallet
        draft.category = utilities
        draft.kind = .bill
        draft.amountVaries = true
        let electricity = try RecurringTransaction.create(draft, today: today, in: context)
        let netflix = try makeSchedule(starting: day(2026, 10, 12))

        let electricityRow = ScheduledOccurrence(
            recurring: electricity, day: day(2026, 10, 12), amount: electricity.startingAmount(among: [])
        )
        let netflixRow = ScheduledOccurrence(
            recurring: netflix, day: day(2026, 10, 12), amount: netflix.startingAmount(among: [])
        )
        #expect(electricityRow.isEstimated)
        #expect(!netflixRow.isEstimated)
    }

    @Test func aVaryingBillsScheduledRowsShowItsEstimateInPlaceOfItsAmount() throws {
        let water = Grosh.Category(name: "Water", type: .expense, symbolName: "bolt", color: .purple)
        context.insert(water)
        for _ in 0..<2 {
            context.insert(Transaction(
                amount: Money(cents: -50_00), day: day(2026, 9, 1), wallet: store.wallet, category: water
            ))
        }
        try context.save()
        let history = try context.fetch(FetchDescriptor<Transaction>())
        var draft = RecurringDraft(startDay: day(2026, 10, 12))
        draft.name = "Water"
        draft.amount = Money(cents: 0)
        draft.wallet = store.wallet
        draft.category = water
        draft.kind = .bill
        draft.amountVaries = true
        draft.estimateCents = AmountEstimate.cents(among: history, for: water, currencyCode: store.wallet.currencyCode)
        let bill = try RecurringTransaction.create(draft, today: today, in: context)

        let rows = [bill].scheduledOccurrences(selection: .total, today: today, history: history)

        #expect(!rows.isEmpty)
        #expect(rows.allSatisfy { $0.amount.cents == -5_000 && $0.isEstimated })
    }

    @Test func theTotalListsOnlyTheWalletsCountedInIt() throws {
        let savings = Wallet(name: "Savings")
        savings.includeInTotal = false
        context.insert(savings)
        let checking = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly)
        let kept = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly, wallet: savings)
        let schedules = [checking, kept]

        let total = schedules.scheduledOccurrences(selection: .total, today: today, history: [])
        let inSavings = schedules.scheduledOccurrences(selection: .wallet(savings), today: today, history: [])

        #expect(total.count == 12)
        #expect(total.allSatisfy { $0.recurring == checking })
        #expect(inSavings.count == 12)
        #expect(inSavings.allSatisfy { $0.recurring == kept })
    }

    @Test func rowsListNewestDayFirst() throws {
        let daily = try makeSchedule(starting: day(2026, 10, 12), preset: .daily)
        let weekly = try makeSchedule(starting: day(2026, 10, 12), preset: .weekly)

        let days = [daily, weekly].scheduledOccurrences(selection: .total, today: today, history: []).map(\.day)

        #expect(days.first == day(2026, 12, 28))
        #expect(days == days.sorted(by: >))
    }

    @Test func aDayListsItsTransactionsThenItsScheduledRowsAndTotalsOnlyTheTransactions() throws {
        let netflix = try makeSchedule(starting: day(2026, 10, 20))
        let rows = [netflix].scheduledOccurrences(selection: .total, today: today, history: [])
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
