import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Reminders on Expected reimbursements (ADR-0010): on by default a week after the Expense, editable per person and
/// switched off, one 09:00 notification each saying who owes what for which Expense, listed by the Home bell from its day
/// until it is settled, and gone once it is paid, closed, forgiven or deleted. Loan, Debt and Estimated-amount reminders
/// are not touched.
@MainActor
@Suite(.namedInTheLog)
struct ExpectedReimbursementReminderTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    /// The 12th of October 2026.
    private var today: CalendarDay { fixture.today }
    private let dinnerDay = day(2026, 10, 3)

    init() throws {
        fixture = try ExpectationFixture()
    }

    /// `hour`:00 on `today`, in UTC.
    private func now(at hour: Int) -> Date {
        Calendar.utcGregorian.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour)) ?? .distantPast
    }

    // MARK: Default, edited and off

    @Test func aNewExpectationRemindsAWeekAfterTheExpensesDay() throws {
        let alex = try fixture.person("Alex")

        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])

        #expect(try fixture.expectation(of: alex, on: dinner).reminderDay == day(2026, 10, 10))
    }

    @Test func movingTheExpensesDayInTheSheetMovesTheDefaultReminderWithIt() throws {
        let alex = try fixture.person("Alex")
        var draft = TransactionDraft(type: .expense, day: dinnerDay)
        draft.people = [alex]
        draft.addOwes(alex)

        draft.day = day(2026, 10, 5)
        #expect(draft.owes[0].reminderDay == day(2026, 10, 12))

        draft.owes[0].reminderDay = day(2026, 10, 20)
        draft.day = day(2026, 10, 6)
        #expect(draft.owes[0].reminderDay == day(2026, 10, 20))
    }

    @Test func theReminderDayCanBeChangedPerPerson() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00), (sam, 30_00)])

        var draft = TransactionDraft(editing: dinner)
        let index = try #require(draft.owes.firstIndex { $0.person === alex })
        draft.owes[index].reminderDay = day(2026, 10, 20)
        try dinner.update(with: draft)

        #expect(try fixture.expectation(of: alex, on: dinner).reminderDay == day(2026, 10, 20))
        #expect(try fixture.expectation(of: sam, on: dinner).reminderDay == day(2026, 10, 10))
    }

    @Test func theReminderCanBeSwitchedOff() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try owed.setReminder(nil)

        #expect(owed.reminderDay == nil)
        #expect(try fixture.owesMe().reminders(from: dinnerDay).isEmpty)
        #expect(try fixture.owesMe().due(on: today).isEmpty)
    }

    // MARK: Notifications

    @Test func theNotificationNamesThePersonTheExpenseAndTheAmount() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00), (sam, nil)])
        dinner.note = "Dinner"

        let reminders = try fixture.owesMe().reminders(from: dinnerDay)

        let byAlex = try #require(reminders.first { $0.personName == "Alex" })
        let bySam = try #require(reminders.first { $0.personName == "Sam" })
        #expect(byAlex.day == day(2026, 10, 10))
        #expect(byAlex.arrival == .onItsDay)
        #expect(byAlex.title == "Owes you")
        #expect(byAlex.body == "Alex owes you \(Money(cents: 30_00).formatted()) for Dinner.")
        #expect(bySam.body == "Sam owes you for Dinner.")
    }

    @Test func theNotificationCarriesWhatAnActionOnItNeeds() throws {
        let alex = try fixture.person("Alex")
        alex.phone = "555 0100"
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        dinner.note = "Dinner"

        let reminder = try #require(fixture.owesMe().reminders(from: dinnerDay).first)

        #expect(ExpectedReimbursementReminder.categoryIdentifier == "grosh.owes-me")
        #expect(reminder.userInfo == [
            "person": "Alex", "phone": "555 0100", "expense": "Dinner", "amountCents": "3000", "currencyCode": "USD",
        ])
        #expect(reminder.original == (try fixture.expectation(of: alex, on: dinner)).persistentModelID)
    }

    @Test func aReminderArrivesAtNineOnItsDay() async throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        try fixture.expectation(of: alex, on: dinner).setReminder(day(2026, 10, 15))
        let scheduler = RecordingReminderScheduler<ExpectedReimbursementReminder>()

        try await fixture.owesMe().reschedule(at: now(at: 8), calendar: .utcGregorian, after: [], using: scheduler)

        let expected = try #require(fixture.owesMe().reminders(from: today).first)
        #expect(scheduler.calls == [.requestPermission, .replacePending([expected])])
        #expect(expected.day == day(2026, 10, 15))
        #expect(expected.arrival == .onItsDay)
    }

    @Test func aReminderForTodayArrivesRightAwayWhenItIsNewAfterNine() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: day(2026, 10, 5), owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        #expect(owed.reminderDay == today)
        let list = try fixture.owesMe()

        let newAfterNine = list.reminders(at: now(at: 14), calendar: .utcGregorian, after: [])
        let arrivedAlready = list.reminders(at: now(at: 14), calendar: .utcGregorian, after: list.reminders(from: today))

        #expect(newAfterNine.map(\.arrival) == [.rightAway])
        #expect(arrivedAlready.isEmpty)
    }

    // MARK: The Home bell

    @Test func theBellListsAnExpectationFromItsReminderDayUntilItIsSettled() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: day(2026, 10, 1), owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        #expect(owed.reminderDay == day(2026, 10, 8))

        #expect(try fixture.owesMe().due(on: day(2026, 10, 7)).isEmpty)
        #expect(try fixture.owesMe().due(on: day(2026, 10, 8)) == [owed])
        #expect(try fixture.owesMe().due(on: today) == [owed])

        try fixture.pay(30_00, on: owed)

        #expect(try fixture.owesMe().due(on: today).isEmpty)
    }

    // MARK: Updating and cancelling

    @Test func settlingForgivingDeletingOrRemovingAnExpectationWithdrawsItsNotification() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let ivan = try fixture.person("Ivan")
        let olga = try fixture.person("Olga")
        let dinner = try fixture.dinner(on: day(2026, 10, 8), owing: [(alex, 30_00), (sam, 20_00), (ivan, nil)])
        let lunch = try fixture.dinner(on: day(2026, 10, 9), owing: [(olga, 10_00)])
        let all = try fixture.owesMe().reminders(from: today)
        #expect(all.count == 4)

        // Paid in full.
        try fixture.pay(30_00, on: fixture.expectation(of: alex, on: dinner))
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName).sorted() == ["Ivan", "Olga", "Sam"])

        // Forgiven, and restored when it is un-forgiven.
        let owedBySam = try fixture.expectation(of: sam, on: dinner)
        try owedBySam.forgive(on: today)
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName).sorted() == ["Ivan", "Olga"])
        try owedBySam.unforgive()
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName).sorted() == ["Ivan", "Olga", "Sam"])

        // Closed by hand.
        try fixture.expectation(of: ivan, on: dinner).close(on: today)
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName).sorted() == ["Olga", "Sam"])

        // Its Expense deleted, and back.
        try lunch.delete(.onlySelected, in: context)
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName) == ["Sam"])
        try lunch.restore()
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName).sorted() == ["Olga", "Sam"])

        // Removed with the Expense's edit.
        var draft = TransactionDraft(editing: lunch)
        draft.removeOwes(olga)
        try lunch.update(with: draft)
        #expect(try fixture.owesMe().reminders(from: today).map(\.personName) == ["Sam"])
    }

    @Test func editingTheReminderChangesTheDayOfItsNotification() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: day(2026, 10, 8), owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        let first = try #require(fixture.owesMe().reminders(from: today).first)

        try owed.setReminder(day(2026, 10, 30))

        let moved = try #require(fixture.owesMe().reminders(from: today).first)
        #expect(first.day == day(2026, 10, 15))
        #expect(moved.day == day(2026, 10, 30))
        #expect(moved.original == first.original)
        #expect(!moved.isSameReminder(as: first))
    }

    // MARK: The other reminders

    @Test func owesMeRemindersLeaveLoanDebtAndEstimatedReminders() throws {
        let alex = try fixture.person("Alex")
        let loan = try fixture.store.lendOrBorrow(.loan, 100_00, on: dinnerDay)
        loan.reminderDay = day(2026, 10, 20)
        try context.save()
        let loanRemindersBefore = try DebtsAndLoans(in: context).reminders(from: today)

        try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])

        #expect(try DebtsAndLoans(in: context).reminders(from: today) == loanRemindersBefore)
        #expect(loanRemindersBefore.count == 1)
        #expect(try DebtsAndLoans(in: context).due(on: today).isEmpty)
        #expect(ExpectedReimbursementReminder.identifierPrefix != DebtReminder.identifierPrefix)
        #expect(ExpectedReimbursementReminder.identifierPrefix != EstimateReminder.identifierPrefix)
    }
}
