import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Reminders on Loans and Debts: which are due (the Home bell), which notifications are pending, and the order of
/// Account → Debts & Loans.
@MainActor
@Suite(.namedInTheLog)
struct DebtReminderTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    /// A Loan (you lent) or Debt (you borrowed) of `cents` with `name`, reminding on `reminderDay`.
    @discardableResult
    private func record(
        _ role: LockedRole, _ cents: Int, with name: String, remindOn reminderDay: CalendarDay?,
        on day: CalendarDay = CalendarDay(year: 2026, month: 5, day: 27)
    ) throws -> Transaction {
        try context.recordLoanOrDebt(
            role, cents, with: context.person(name), on: day, in: store.checking, remindOn: reminderDay
        )
    }

    /// The Person `original` is with, as a reminder names them.
    private func personID(of original: Transaction) -> PersistentIdentifier? {
        original.orderedPeople.first?.persistentModelID
    }

    /// What is still outstanding on `original`, a Loan or Debt, as every screen works it out.
    private func outstanding(_ original: Transaction) throws -> Money {
        try #require(try LoanOrDebt(original)).outstanding
    }

    // MARK: Due (the Home bell)

    @Test func openLoansAndDebtsRemindingTodayOrEarlierAreDueEarliestFirst() throws {
        let pasha = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let anna = try record(.debt, 50_00, with: "Anna", remindOn: today.adding(days: -3))
        try record(.loan, 20_00, with: "Ivan", remindOn: today.adding(days: 1))
        try record(.loan, 30_00, with: "Olga", remindOn: nil)

        let due = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).due(on: today)

        #expect(due.map(\.original) == [anna, pasha])
    }

    @Test func aSettledLoanIsNeverDue() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: -1))

        try context.pay(100_00, on: loan, on: today)

        #expect(DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).due(on: today).isEmpty)
    }

    // MARK: Notifications

    @Test func eachOpenLoanOrDebtRemindingTodayOrLaterHasANotificationOnItsDay() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))
        try context.pay(60_00, on: loan, on: today)
        let anna = try record(.debt, 50_00, with: "Anna", remindOn: today)
        try record(.loan, 20_00, with: "Ivan", remindOn: today.adding(days: -1))
        try record(.loan, 30_00, with: "Olga", remindOn: nil)

        let reminders = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today)

        #expect(reminders == [
            DebtReminder(
                original: anna.persistentModelID, day: today, person: personID(of: anna), withName: "Anna",
                outstanding: Money(cents: 50_00), kind: .debt
            ),
            DebtReminder(
                original: loan.persistentModelID, day: today.adding(days: 5), person: personID(of: loan),
                withName: "Pasha", outstanding: Money(cents: 40_00), kind: .loan
            ),
        ])
        #expect(reminders.allSatisfy { $0.arrival == .onItsDay })
    }

    @Test func settlingALoanWithdrawsItsNotification() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))

        var forgive = try ForgiveDraft(forgiving: loan, on: today)
        forgive.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(forgive, in: context)

        #expect(DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today).isEmpty)
    }

    @Test func theFirstReminderAsksToSendNotificationsThenIsScheduledOnceAllowed() async throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))
        let scheduler = RecordingReminderScheduler<DebtReminder>()

        try await DebtsAndLoans(context.fetch(DebtsAndLoans.records)).reschedule(
            at: moment(today, at: 8), calendar: .utcGregorian, after: [], using: scheduler
        )

        #expect(scheduler.calls == [
            .requestPermission,
            .replacePending([
                DebtReminder(
                    original: loan.persistentModelID, day: today.adding(days: 5), person: personID(of: loan),
                    withName: "Pasha",
                    outstanding: Money(cents: 100_00), kind: .loan
                ),
            ]),
        ])
    }

    @Test func withNoReminderToSendNothingAsksToSendNotifications() async throws {
        try record(.loan, 100_00, with: "Pasha", remindOn: nil)
        let scheduler = RecordingReminderScheduler<DebtReminder>()

        try await DebtsAndLoans(context.fetch(DebtsAndLoans.records)).reschedule(
            at: moment(today, at: 8), calendar: .utcGregorian, after: [], using: scheduler
        )

        #expect(scheduler.calls == [.replacePending([])])
    }

    @Test func aReminderForTodayArrivesAtNineOrRightAwayWhenSetAfterNine() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let list = DebtsAndLoans(try context.fetch(DebtsAndLoans.records))

        let setBeforeNine = list.reminders(at: moment(today, at: 8), calendar: .utcGregorian, after: [])
        let setAfterNine = list.reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: [])

        #expect(setBeforeNine.map(\.arrival) == [.onItsDay])
        #expect(setAfterNine.map(\.arrival) == [.rightAway])
        #expect(setAfterNine.map(\.original) == [loan.persistentModelID])
    }

    @Test func aReminderForTodayThatHasArrivedIsNotSentAgain() throws {
        try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let list = DebtsAndLoans(try context.fetch(DebtsAndLoans.records))
        let sentAtNine = list.reminders(from: today)

        #expect(list.reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: sentAtNine).isEmpty)
        // On launch nothing was handed over yet in this run, but a reminder from an earlier run has arrived.
        #expect(list.reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: nil).isEmpty)
    }

    @Test func movingAReminderToTodayAfterNineSendsItRightAway() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 7))
        let beforeTheMove = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today)

        try loan.setReminder(today)

        let handed = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: beforeTheMove)
        #expect(handed.map(\.arrival) == [.rightAway])
    }

    // MARK: Changing the reminder later

    @Test func aLoanWithPaymentsCanStillMoveItsReminder() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        try context.pay(60_00, on: loan, on: today)

        try loan.setReminder(today.adding(days: 30))

        #expect(loan.reminderDay == today.adding(days: 30))
        #expect(loan.amountCents == -100_00)
        #expect(try outstanding(loan) == Money(cents: 40_00))
    }

    @Test func onlyALoanOrDebtTakesAReminder() throws {
        let coffee = store.spend(4_50, on: try store.category("Café"))

        #expect(throws: DebtLoanRuleError.notALoanOrDebt) { try coffee.setReminder(today) }
        #expect(coffee.reminderDay == nil)
    }

    // MARK: Debts & Loans order

    @Test func openOnesWithADueDateComeFirstSoonestFirstThenTheRestOldestFirst() throws {
        let late = try record(.loan, 10_00, with: "Late", remindOn: today.adding(days: 9), on: today.adding(days: -1))
        let soon = try record(.loan, 10_00, with: "Soon", remindOn: today.adding(days: 2), on: today)
        let newer = try record(.debt, 10_00, with: "Newer", remindOn: nil, on: today.adding(days: -5))
        let older = try record(.debt, 10_00, with: "Older", remindOn: nil, on: today.adding(days: -50))

        #expect(DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).open.map(\.original) == [soon, late, older, newer])
    }

    // MARK: People

    @Test func theReminderNamesThePersonTheLoanIsWith() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))
        let pasha = try #require(loan.orderedPeople.first)
        pasha.rename(to: "Pavel")

        let reminders = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today)

        #expect(reminders.map(\.withName) == ["Pavel"])
        #expect(reminders.first?.body.contains("Pavel") == true)
    }
}
