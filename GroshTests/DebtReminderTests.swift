import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Reminders on Loans and Debts: which are due (the Home bell), which notifications are pending, and the order of
/// Account → Debts & Loans.
@MainActor
struct DebtReminderTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// A Loan (you lent) or Debt (you borrowed) of `cents` with `name`, reminding on `reminderDay`.
    @discardableResult
    private func record(
        _ role: LockedRole, _ cents: Int, with name: String, remindOn reminderDay: CalendarDay?,
        on day: CalendarDay = CalendarDay(year: 2026, month: 5, day: 27)
    ) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: day)
        draft.wallet = store.wallet
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.withName = name
        draft.reminderDay = reminderDay
        return try Transaction.create(draft, in: context)
    }

    private func pay(_ cents: Int, on original: Transaction) throws {
        var draft = try DebtPaymentDraft(settling: original, on: today, in: context)
        draft.amount = Money(cents: cents)
        try DebtPayment.record(draft, in: context)
    }

    /// What is still outstanding on `original`, a Loan or Debt, as every screen works it out.
    private func outstanding(_ original: Transaction) throws -> Money {
        try #require(try LoanOrDebt(original, in: context)).outstanding
    }

    // MARK: Due (the Home bell)

    @Test func openLoansAndDebtsRemindingTodayOrEarlierAreDueEarliestFirst() throws {
        let pasha = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let anna = try record(.debt, 50_00, with: "Anna", remindOn: today.adding(days: -3))
        try record(.loan, 20_00, with: "Ivan", remindOn: today.adding(days: 1))
        try record(.loan, 30_00, with: "Olga", remindOn: nil)

        let due = try DebtsAndLoans(in: context).due(on: today)

        #expect(due.map(\.original) == [anna, pasha])
    }

    @Test func aSettledLoanIsNeverDue() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: -1))

        try pay(100_00, on: loan)

        #expect(try DebtsAndLoans(in: context).due(on: today).isEmpty)
    }

    // MARK: Notifications

    @Test func eachOpenLoanOrDebtRemindingTodayOrLaterHasANotificationOnItsDay() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))
        try pay(60_00, on: loan)
        let anna = try record(.debt, 50_00, with: "Anna", remindOn: today)
        try record(.loan, 20_00, with: "Ivan", remindOn: today.adding(days: -1))
        try record(.loan, 30_00, with: "Olga", remindOn: nil)

        let reminders = try DebtsAndLoans(in: context).reminders(from: today)

        #expect(reminders == [
            DebtReminder(
                original: anna.persistentModelID, day: today, withName: "Anna", outstanding: Money(cents: 50_00),
                kind: .debt
            ),
            DebtReminder(
                original: loan.persistentModelID, day: today.adding(days: 5), withName: "Pasha",
                outstanding: Money(cents: 40_00), kind: .loan
            ),
        ])
        #expect(reminders.allSatisfy { $0.arrival == .onItsDay })
    }

    @Test func settlingALoanWithdrawsItsNotification() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))

        var forgive = try ForgiveDraft(forgiving: loan, on: today, in: context)
        forgive.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(forgive, in: context)

        #expect(try DebtsAndLoans(in: context).reminders(from: today).isEmpty)
    }

    /// `hour`:00 on `today`, in UTC.
    private func now(at hour: Int) -> Date {
        Calendar.utcGregorian.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: hour)) ?? .distantPast
    }

    @Test func theFirstReminderAsksToSendNotificationsThenIsScheduledOnceAllowed() async throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 5))
        let scheduler = RecordingReminderScheduler()

        try await DebtsAndLoans(in: context).reschedule(
            at: now(at: 8), calendar: .utcGregorian, after: [], using: scheduler
        )

        #expect(scheduler.calls == [
            .requestPermission,
            .replacePendingReminders([
                DebtReminder(
                    original: loan.persistentModelID, day: today.adding(days: 5), withName: "Pasha",
                    outstanding: Money(cents: 100_00), kind: .loan
                ),
            ]),
        ])
    }

    @Test func withNoReminderToSendNothingAsksToSendNotifications() async throws {
        try record(.loan, 100_00, with: "Pasha", remindOn: nil)
        let scheduler = RecordingReminderScheduler()

        try await DebtsAndLoans(in: context).reschedule(
            at: now(at: 8), calendar: .utcGregorian, after: [], using: scheduler
        )

        #expect(scheduler.calls == [.replacePendingReminders([])])
    }

    @Test func aReminderForTodayArrivesAtNineOrRightAwayWhenSetAfterNine() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let list = try DebtsAndLoans(in: context)

        let setBeforeNine = list.reminders(at: now(at: 8), calendar: .utcGregorian, after: [])
        let setAfterNine = list.reminders(at: now(at: 14), calendar: .utcGregorian, after: [])

        #expect(setBeforeNine.map(\.arrival) == [.onItsDay])
        #expect(setAfterNine.map(\.arrival) == [.rightAway])
        #expect(setAfterNine.map(\.original) == [loan.persistentModelID])
    }

    @Test func aReminderForTodayThatHasArrivedIsNotSentAgain() throws {
        try record(.loan, 100_00, with: "Pasha", remindOn: today)
        let list = try DebtsAndLoans(in: context)
        let sentAtNine = list.reminders(from: today)

        #expect(list.reminders(at: now(at: 14), calendar: .utcGregorian, after: sentAtNine).isEmpty)
        // On launch nothing was handed over yet in this run, but a reminder from an earlier run has arrived.
        #expect(list.reminders(at: now(at: 14), calendar: .utcGregorian, after: nil).isEmpty)
    }

    @Test func movingAReminderToTodayAfterNineSendsItRightAway() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today.adding(days: 7))
        let beforeTheMove = try DebtsAndLoans(in: context).reminders(from: today)

        try loan.setReminder(today)

        let handed = try DebtsAndLoans(in: context).reminders(at: now(at: 14), calendar: .utcGregorian, after: beforeTheMove)
        #expect(handed.map(\.arrival) == [.rightAway])
    }

    // MARK: Changing the reminder later

    @Test func aLoanWithPaymentsCanStillMoveItsReminder() throws {
        let loan = try record(.loan, 100_00, with: "Pasha", remindOn: today)
        try pay(60_00, on: loan)

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

        #expect(try DebtsAndLoans(in: context).open.map(\.original) == [soon, late, older, newer])
    }
}

/// Records what it is asked, in order, instead of asking the user or scheduling notifications. Notifications are
/// always allowed.
@MainActor
private final class RecordingReminderScheduler: ReminderScheduler {
    enum Call: Equatable {
        case requestPermission
        case replacePendingReminders([DebtReminder])
    }

    private(set) var calls: [Call] = []

    func requestPermission() async -> Bool {
        calls.append(.requestPermission)
        return true
    }

    func replacePendingReminders(with reminders: [DebtReminder]) async {
        calls.append(.replacePendingReminders(reminders))
    }
}
