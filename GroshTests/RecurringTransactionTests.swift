import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Recurring transactions: which transactions a schedule makes, on which day and with which fields, and what editing
/// or deleting it changes.
@MainActor
struct RecurringTransactionTests {
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

    private func category(_ name: String, _ type: CategoryType) -> Category {
        let category = Category(name: name, type: type, symbolName: "repeat", color: .purple)
        context.insert(category)
        return category
    }

    /// A monthly Netflix of 15.99 starting on `start`, paid from the fixture's wallet.
    private func netflix(starting start: CalendarDay) -> RecurringDraft {
        var draft = RecurringDraft(startDay: start)
        draft.name = "Netflix"
        draft.amount = Money(cents: 1599)
        draft.wallet = store.wallet
        draft.category = category("Subscriptions", .expense)
        draft.note = "  family plan  "
        return draft
    }

    @Test func aScheduleStartingLaterMakesItsTransactionOnTheDueDayOnly() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 10, 12)), today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 11), in: context)
        #expect(recurring.attachedTransactions.isEmpty)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 10, 12)])
    }

    @Test func theTransactionMadeCarriesTheSchedulesFieldsAndAnExpenseSign() throws {
        let card = Card(name: "Visa", kind: .credit, payingWallet: store.wallet)
        context.insert(card)
        var draft = netflix(starting: day(2026, 10, 12))
        draft.card = card
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        let transaction = try #require(recurring.attachedTransactions.first)
        #expect(transaction.amountCents == -1599)
        #expect(transaction.wallet == store.wallet)
        #expect(transaction.category?.name == "Subscriptions")
        #expect(transaction.card == card)
        #expect(transaction.note == "family plan")
        #expect(transaction.recurring == recurring)
    }

    @Test func anIncomeCategoryMakesPositiveTransactions() throws {
        var draft = netflix(starting: day(2026, 10, 12))
        draft.type = .income
        draft.category = category("Salary", .income)
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        #expect(recurring.attachedTransactions.map(\.amountCents) == [1599])
    }

    /// Saving on October 9 with a monthly schedule from September 1: September 1 and October 1 are past, so only
    /// November 1 onwards is made.
    @Test func occurrencesDatedOnOrBeforeSavingAreNotMade() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 9, 1)), today: today, in: context)

        #expect(recurring.nextDueDay == day(2026, 11, 1))
        try RecurringTransaction.catchUp(through: today, in: context)
        #expect(recurring.attachedTransactions.isEmpty)

        try RecurringTransaction.catchUp(through: day(2026, 11, 1), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 11, 1)])
    }

    @Test func everyDayMissedWhileTheAppWasClosedIsMadeWhenItOpens() throws {
        var draft = netflix(starting: today)
        draft.preset = .daily
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        // Saving on October 9 skips October 9 itself; the app next opens on October 12.
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        #expect(recurring.attachedTransactions.map(\.day) == [
            day(2026, 10, 12), day(2026, 10, 11), day(2026, 10, 10),
        ])
    }

    @Test func editingChangesOnlyTheOccurrencesStillToCome() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 10, 12)), today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        var edited = RecurringDraft(editing: recurring)
        edited.amount = Money(cents: 2000)
        try recurring.update(with: edited, today: day(2026, 10, 13))
        try RecurringTransaction.catchUp(through: day(2026, 11, 12), in: context)

        // October 12 keeps the amount it was made with; November 12 is made with the new one.
        #expect(recurring.attachedTransactions.map(\.amountCents) == [-2000, -1599])
    }

    @Test func aScheduleThatHasRunOutHasNoNextDay() throws {
        var draft = netflix(starting: day(2026, 10, 12))
        draft.endKind = .afterCount
        draft.occurrenceCount = 2
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        try RecurringTransaction.catchUp(through: day(2026, 12, 31), in: context)

        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 11, 12), day(2026, 10, 12)])
        #expect(recurring.nextDueDay == nil)
    }

    @Test func deletingTheScheduleKeepsWhatItMadeAsOrdinaryTransactions() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 10, 12)), today: today, in: context)
        try RecurringTransaction.catchUp(through: day(2026, 10, 12), in: context)

        try recurring.delete(today: day(2026, 10, 12), in: context)
        try RecurringTransaction.catchUp(through: day(2026, 12, 31), in: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.count == 1)
        #expect(transactions.first?.recurring == nil)
    }

    /// Nothing has run since October 12, so the October 12 transaction is still owed when the edit comes. It is made
    /// with the amount the schedule had, not the edited one.
    @Test func anEditMakesWhatFellDueUnderTheOldScheduleFirst() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 10, 12)), today: today, in: context)

        var edited = RecurringDraft(editing: recurring)
        edited.amount = Money(cents: 2000)
        try recurring.update(with: edited, today: day(2026, 10, 12))

        #expect(recurring.attachedTransactions.map(\.amountCents) == [-1599])
    }

    @Test func deletingMakesWhatFellDueFirst() throws {
        let recurring = try RecurringTransaction.create(netflix(starting: day(2026, 10, 12)), today: today, in: context)

        try recurring.delete(today: day(2026, 10, 12), in: context)

        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        #expect(transactions.map(\.amountCents) == [-1599])
        #expect(transactions.first?.recurring == nil)
    }

    @Test func aCardFromAnotherWalletIsRefused() {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        let card = Card(name: "Amex", kind: .credit, payingWallet: savings)
        context.insert(card)
        var draft = netflix(starting: day(2026, 10, 12))
        draft.card = card

        #expect(throws: RecurringRuleError.cardNotInWallet) { try draft.validate() }
    }

    @Test func anEndDateBeforeTheStartIsRefused() {
        var draft = netflix(starting: day(2026, 10, 12))
        draft.endKind = .until
        draft.untilDay = day(2026, 10, 11)

        #expect(throws: RecurringRuleError.untilBeforeStart) { try draft.validate() }
    }

    @Test func aDraftNeedsANameAWalletAndAnAmount() {
        var draft = netflix(starting: day(2026, 10, 12))
        draft.name = "   "
        #expect(throws: RecurringRuleError.missingName) { try draft.validate() }

        draft.name = "Netflix"
        draft.amount = Money(cents: 0)
        #expect(throws: RecurringRuleError.missingAmount) { try draft.validate() }

        draft.amount = Money(cents: 1599)
        draft.wallet = nil
        #expect(throws: RecurringRuleError.missingWallet) { try draft.validate() }
    }

    /// The monthly day is saved with the schedule, comes back into the form when it is edited, and makes its
    /// transactions on the day it names.
    @Test func aMonthlyDayIsSavedWithTheRepeat() throws {
        var draft = netflix(starting: day(2026, 10, 29))
        draft.monthlyDay = .nthWeekday
        let recurring = try RecurringTransaction.create(draft, today: today, in: context)

        #expect(recurring.schedule.monthlyDay == .nthWeekday)
        #expect(RecurringDraft(editing: recurring).monthlyDay == .nthWeekday)

        try RecurringTransaction.catchUp(through: day(2026, 11, 26), in: context)
        #expect(recurring.attachedTransactions.map(\.day) == [day(2026, 11, 26), day(2026, 10, 29)])
    }

    /// The last day is offered only from the 28th, so moving the start below it drops a last day already picked.
    @Test func movingTheStartBelowTheTwentyEighthDropsTheLastDay() {
        var draft = netflix(starting: day(2026, 1, 28))
        draft.monthlyDay = .lastDay

        draft.startDay = day(2026, 1, 15)

        #expect(draft.monthlyDay == .sameDay)
    }

    /// A schedule is not a transaction: saving one, with its past occurrences skipped, adds none to the transactions.
    @Test func aScheduleIsNotATransaction() throws {
        try RecurringTransaction.create(netflix(starting: day(2026, 9, 1)), today: today, in: context)

        #expect(try context.fetch(FetchDescriptor<Transaction>()).isEmpty)
    }
}
