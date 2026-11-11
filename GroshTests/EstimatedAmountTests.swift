import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Varying Bills: the transactions they make as estimates, when those are reminded of, and what confirming the amount
/// clears.
@MainActor
@Suite(.namedInTheLog)
struct EstimatedAmountTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    /// The day the schedules are saved on: occurrences dated on or before it aren't made.
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    /// Records a September expense of `cents` under `category`, so there is history for an estimate to average.
    private func record(_ cents: Int, under category: Grosh.Category) throws {
        context.record(-cents, on: day(2026, 9, 1), in: store.checking, under: category)
        try context.save()
    }

    /// An electricity Bill of 25.00 starting October 12, monthly, paid from the fixture's wallet.
    private func electricity(
        under category: Grosh.Category, varies: Bool = true, remindAfter: Int = 2
    ) -> RecurringDraft {
        var draft = RecurringDraft(startDay: day(2026, 10, 12))
        draft.name = "Electricity"
        draft.amount = Money(cents: 2_500)
        draft.wallet = store.checking
        draft.category = category
        draft.kind = .bill
        draft.amountVaries = varies
        draft.remindAfterDays = remindAfter
        return draft
    }

    /// The October 12 transaction a varying electricity Bill makes, with no history to average.
    private func estimatedElectricity() throws -> Transaction {
        let utilities = context.addCategory("Utilities")
        let recurring = try RecurringTransaction.create(electricity(under: utilities), today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        return try #require(recurring.attachedTransactions.first)
    }

    @Test func aVaryingBillMakesAnEstimatedTransactionAtTheAverageOfItsCategory() throws {
        let utilities = context.addCategory("Utilities")
        try record(1_000, under: utilities)
        try record(3_000, under: utilities)
        let recurring = try RecurringTransaction.create(electricity(under: utilities), today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.amountCents == -2_000)
        #expect(made.isEstimated)
        #expect(made.estimateReminderDay == day(2026, 10, 14))
    }

    @Test func aVaryingBillWithNoHistoryMakesItsTypedAmountStillEstimated() throws {
        let made = try estimatedElectricity()

        #expect(made.amountCents == -2_500)
        #expect(made.isEstimated)
    }

    @Test func aVaryingBillNeedsNoTypedAmountWhenItsCategoryHasAnEstimate() throws {
        let water = context.addCategory("Water")
        try record(5_000, under: water)
        try record(5_000, under: water)
        var draft = electricity(under: water)
        draft.name = "Water"
        draft.amount = Money(cents: 0)

        #expect(draft.estimateCents == 5_000)
        #expect(draft.canSave)

        let recurring = try RecurringTransaction.create(draft, today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.amountCents == -5_000)
        #expect(made.isEstimated)
    }

    @Test func aVaryingBillWithNoEstimateAndNoAmountCannotBeSaved() {
        var draft = electricity(under: context.addCategory("Water"))
        draft.amount = Money(cents: 0)
        #expect(!draft.canSave)
    }

    @Test func aFixedBillNeedsItsAmountEvenWhenItsCategoryHasHistory() throws {
        let water = context.addCategory("Water")
        try record(5_000, under: water)
        var draft = electricity(under: water, varies: false)
        draft.amount = Money(cents: 0)

        #expect(draft.estimateCents == nil)
        #expect(!draft.canSave)
    }

    @Test func theEstimateFollowsTheCategoryAndWhetherTheAmountVaries() throws {
        let water = context.addCategory("Water")
        let gas = context.addCategory("Gas")
        try record(5_000, under: water)
        try record(1_000, under: gas)
        var draft = electricity(under: water)
        #expect(draft.estimateCents == 5_000)

        draft.category = gas
        #expect(draft.estimateCents == 1_000)

        draft.amountVaries = false
        #expect(draft.estimateCents == nil)

        draft.amountVaries = true
        draft.kind = .regular
        #expect(draft.estimateCents == nil)
    }

    @Test func aRowShowsTheEstimateOnceThereIsHistoryAndTheTypedAmountUntilThen() throws {
        let utilities = context.addCategory("Utilities")
        let varying = try RecurringTransaction.create(electricity(under: utilities), today: today, in: context)
        let fixed = try RecurringTransaction.create(
            electricity(under: utilities, varies: false), today: today, in: context
        )
        #expect(varying.startingAmount(among: []).cents == -2_500)

        try record(5_000, under: utilities)
        let history = try context.fetch(FetchDescriptor<Transaction>())

        #expect(varying.startingAmount(among: history).cents == -5_000)
        #expect(fixed.startingAmount(among: history).cents == -2_500)
    }

    @Test func theReminderComesTheChosenNumberOfDaysAfterTheOccurrence() throws {
        let utilities = context.addCategory("Utilities")
        let recurring = try RecurringTransaction.create(
            electricity(under: utilities, remindAfter: 5), today: today, in: context
        )

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.estimateReminderDay == day(2026, 10, 17))
    }

    @Test func aFixedBillMakesItsTypedAmountWithNoEstimate() throws {
        let utilities = context.addCategory("Utilities")
        try record(1_000, under: utilities)
        let recurring = try RecurringTransaction.create(
            electricity(under: utilities, varies: false), today: today, in: context
        )

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.amountCents == -2_500)
        #expect(!made.isEstimated)
        #expect(made.estimateReminderDay == nil)
    }

    @Test func aSubscriptionIgnoresAmountVaries() throws {
        let utilities = context.addCategory("Utilities")
        var draft = electricity(under: utilities)
        draft.kind = .subscription
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(!made.isEstimated)
    }

    @Test func confirmingTheAmountClearsTheMarkItsReminderAndTheBellItem() throws {
        let made = try estimatedElectricity()
        #expect(try context.fetch(EstimatedAmounts.records).count == 1)
        #expect(EstimatedAmounts([made]).due(on: day(2026, 10, 14)).count == 1)

        try made.confirmAmount(cents: 2_750)

        #expect(made.amountCents == -2_750)
        #expect(!made.isEstimated)
        #expect(made.estimateReminderDay == nil)
        #expect(EstimatedAmounts([made]).due(on: day(2026, 10, 20)).isEmpty)
        #expect(try context.fetch(EstimatedAmounts.records).isEmpty)
    }

    @Test func editingTheAmountClearsTheMarkButEditingOnlyTheNoteKeepsIt() throws {
        let made = try estimatedElectricity()

        var noteOnly = TransactionDraft(editing: made)
        noteOnly.note = "Winter rate"
        try made.update(with: noteOnly)
        #expect(made.isEstimated)

        var amountEdit = TransactionDraft(editing: made)
        amountEdit.amount = Money(cents: 4_000)
        try made.update(with: amountEdit)
        #expect(made.amountCents == -4_000)
        #expect(!made.isEstimated)
        #expect(made.estimateReminderDay == nil)
    }

    @Test func theRemindersAreThoseDueFromTheReminderDayOn() throws {
        let made = try estimatedElectricity()
        let estimates = EstimatedAmounts([made])

        #expect(estimates.due(on: day(2026, 10, 13)).isEmpty)
        #expect(estimates.due(on: day(2026, 10, 14)).count == 1)
        #expect(estimates.reminders(from: today).count == 1)
        #expect(estimates.reminders(from: day(2026, 10, 15)).isEmpty)
    }

    @Test func aReminderCarriesTheBillsNameAndItsEstimate() throws {
        let made = try estimatedElectricity()

        let reminder = try #require(EstimatedAmounts([made]).reminders(from: today).first)

        #expect(reminder.original == made.persistentModelID)
        #expect(reminder.day == day(2026, 10, 14))
        #expect(reminder.name == "Electricity")
        #expect(reminder.estimate == Money(cents: 2_500, currencyCode: "USD"))
    }

    @Test func aReminderArrivesOnItsDayAtNineOrRightAwayWhenSetAfterNine() throws {
        let made = try estimatedElectricity()
        let estimates = EstimatedAmounts([made])
        let reminderDay = day(2026, 10, 14)

        let beforeNine = estimates.reminders(at: moment(reminderDay, at: 8), calendar: .utcGregorian, after: [])
        #expect(beforeNine.map(\.arrival) == [.onItsDay])

        let afterNine = estimates.reminders(at: moment(reminderDay, at: 14), calendar: .utcGregorian, after: [])
        #expect(afterNine.map(\.arrival) == [.rightAway])

        let handedOver = estimates.reminders(at: moment(reminderDay, at: 15), calendar: .utcGregorian, after: afterNine)
        #expect(handedOver.isEmpty)
    }

    @Test func theFirstReminderAsksToSendNotificationsThenIsScheduled() async throws {
        let made = try estimatedElectricity()
        let scheduler = RecordingReminderScheduler<EstimateReminder>()

        await EstimatedAmounts([made]).reschedule(
            at: moment(day(2026, 10, 14), at: 8), calendar: .utcGregorian, after: nil, using: scheduler
        )

        #expect(scheduler.calls == [
            .requestPermission,
            .replacePending([
                EstimateReminder(
                    original: made.persistentModelID, day: day(2026, 10, 14), name: "Electricity",
                    estimate: Money(cents: 2_500, currencyCode: "USD")
                ),
            ]),
        ])
    }

    @Test func withNoEstimateToRemindOfNothingAsksToSendNotifications() async throws {
        let none: [Transaction] = []
        let scheduler = RecordingReminderScheduler<EstimateReminder>()

        await EstimatedAmounts(none).reschedule(
            at: moment(day(2026, 10, 14), at: 8), calendar: .utcGregorian, after: nil, using: scheduler
        )

        #expect(scheduler.calls == [.replacePending([])])
    }
}

