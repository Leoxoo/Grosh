import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Varying Bills: the transactions they make as estimates, when those are reminded of, and what confirming the amount
/// clears.
@MainActor
struct EstimatedAmountTests {
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

    /// The instant at `hour` o'clock on `when`, in the UTC calendar the reminders are tested on.
    private func at(_ when: CalendarDay, hour: Int) -> Date {
        Calendar.utcGregorian.date(from: DateComponents(year: when.year, month: when.month, day: when.day, hour: hour))
            ?? .distantPast
    }

    private func category(_ name: String) -> Grosh.Category {
        let category = Grosh.Category(name: name, type: .expense, symbolName: "bolt", color: .purple)
        context.insert(category)
        return category
    }

    /// Records a September expense of `cents` under `category`, so there is history for an estimate to average.
    private func record(_ cents: Int, under category: Grosh.Category) throws {
        let transaction = Transaction(
            amount: Money(cents: -cents), day: day(2026, 9, 1), wallet: store.wallet, category: category
        )
        context.insert(transaction)
        try context.save()
    }

    /// An electricity Bill of 25.00 starting October 12, monthly, paid from the fixture's wallet.
    private func electricity(
        under category: Grosh.Category, varies: Bool = true, remindAfter: Int = 2
    ) -> RecurringDraft {
        var draft = RecurringDraft(startDay: day(2026, 10, 12))
        draft.name = "Electricity"
        draft.amount = Money(cents: 2_500)
        draft.wallet = store.wallet
        draft.category = category
        draft.kind = .bill
        draft.amountVaries = varies
        draft.remindAfterDays = remindAfter
        return draft
    }

    /// The October 12 transaction a varying electricity Bill makes, with no history to average.
    private func estimatedElectricity() throws -> Transaction {
        let utilities = category("Utilities")
        let recurring = try RecurringTransaction.create(electricity(under: utilities), today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        return try #require(recurring.attachedTransactions.first)
    }

    /// The average the editor shows for `category`, which it sets on the draft as the estimate.
    private func estimate(for category: Grosh.Category) throws -> Int? {
        try context.save()
        return AmountEstimate.cents(
            among: try context.fetch(FetchDescriptor<Transaction>()), for: category,
            currencyCode: store.wallet.currencyCode
        )
    }

    @Test func aVaryingBillMakesAnEstimatedTransactionAtTheAverageOfItsCategory() throws {
        let utilities = category("Utilities")
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
        let water = category("Water")
        try record(5_000, under: water)
        try record(5_000, under: water)
        var draft = electricity(under: water)
        draft.name = "Water"
        draft.amount = Money(cents: 0)
        #expect(!draft.canSave)

        draft.estimateCents = try estimate(for: water)
        #expect(draft.canSave)

        let recurring = try RecurringTransaction.create(draft, today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.amountCents == -5_000)
        #expect(made.isEstimated)
    }

    @Test func aVaryingBillWithNoEstimateAndNoAmountCannotBeSaved() {
        var draft = electricity(under: category("Water"))
        draft.amount = Money(cents: 0)
        #expect(!draft.canSave)
    }

    @Test func aFixedBillNeedsItsAmountEvenWhenThereIsAnEstimate() {
        var draft = electricity(under: category("Water"), varies: false)
        draft.amount = Money(cents: 0)
        draft.estimateCents = 5_000
        #expect(!draft.canSave)
    }

    @Test func theReminderComesTheChosenNumberOfDaysAfterTheOccurrence() throws {
        let utilities = category("Utilities")
        let recurring = try RecurringTransaction.create(
            electricity(under: utilities, remindAfter: 5), today: today, in: context
        )

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(made.estimateReminderDay == day(2026, 10, 17))
    }

    @Test func aFixedBillMakesItsTypedAmountWithNoEstimate() throws {
        let utilities = category("Utilities")
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
        let utilities = category("Utilities")
        var draft = electricity(under: utilities)
        draft.kind = .subscription
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let made = try #require(recurring.attachedTransactions.first)
        #expect(!made.isEstimated)
    }

    @Test func confirmingTheAmountClearsTheMarkItsReminderAndTheBellItem() throws {
        let made = try estimatedElectricity()
        #expect(try context.fetch(EstimatedAmounts.transactions).count == 1)
        #expect(EstimatedAmounts([made]).due(on: day(2026, 10, 14)).count == 1)

        try made.confirmAmount(cents: 2_750)

        #expect(made.amountCents == -2_750)
        #expect(!made.isEstimated)
        #expect(made.estimateReminderDay == nil)
        #expect(EstimatedAmounts([made]).due(on: day(2026, 10, 20)).isEmpty)
        #expect(try context.fetch(EstimatedAmounts.transactions).isEmpty)
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

        let beforeNine = estimates.reminders(at: at(reminderDay, hour: 8), calendar: .utcGregorian, after: [])
        #expect(beforeNine.map(\.arrival) == [.onItsDay])

        let afterNine = estimates.reminders(at: at(reminderDay, hour: 14), calendar: .utcGregorian, after: [])
        #expect(afterNine.map(\.arrival) == [.rightAway])

        let handedOver = estimates.reminders(at: at(reminderDay, hour: 15), calendar: .utcGregorian, after: afterNine)
        #expect(handedOver.isEmpty)
    }

    @Test func theFirstReminderAsksToSendNotificationsThenIsScheduled() async throws {
        let made = try estimatedElectricity()
        let scheduler = RecordingEstimateScheduler()

        await EstimatedAmounts([made]).reschedule(
            at: at(day(2026, 10, 14), hour: 8), calendar: .utcGregorian, after: nil, using: scheduler
        )

        #expect(scheduler.calls == [
            .requestPermission,
            .replacePendingEstimateReminders([
                EstimateReminder(
                    original: made.persistentModelID, day: day(2026, 10, 14), name: "Electricity",
                    estimate: Money(cents: 2_500, currencyCode: "USD")
                ),
            ]),
        ])
    }

    @Test func withNoEstimateToRemindOfNothingAsksToSendNotifications() async throws {
        let none: [Transaction] = []
        let scheduler = RecordingEstimateScheduler()

        await EstimatedAmounts(none).reschedule(
            at: at(day(2026, 10, 14), hour: 8), calendar: .utcGregorian, after: nil, using: scheduler
        )

        #expect(scheduler.calls == [.replacePendingEstimateReminders([])])
    }
}

/// Records what it is asked, instead of asking the user or scheduling notifications. Notifications are always allowed.
@MainActor
private final class RecordingEstimateScheduler: ReminderScheduler {
    enum Call: Equatable {
        case requestPermission
        case replacePendingEstimateReminders([EstimateReminder])
    }

    private(set) var calls: [Call] = []

    func requestPermission() async -> Bool {
        calls.append(.requestPermission)
        return true
    }

    func replacePendingReminders(with reminders: [DebtReminder]) async {}

    func replacePendingEstimateReminders(with reminders: [EstimateReminder]) async {
        calls.append(.replacePendingEstimateReminders(reminders))
    }
}
