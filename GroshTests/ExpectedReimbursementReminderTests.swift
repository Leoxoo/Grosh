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
        #expect(byAlex.body == "Alex owes you $30.00 for Dinner.")
        #expect(bySam.body == "Sam owes you for Dinner.")
    }

    @Test func theNotificationCarriesWhatAnActionOnItNeeds() throws {
        let alex = try fixture.person("Alex")
        alex.phone = "555 0100"
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        dinner.note = "Dinner"

        let reminder = try #require(fixture.owesMe().reminders(from: dinnerDay).first)

        #expect(reminder.textThem == TextThemPayload(
            person: alex.persistentModelID, personName: "Alex", phone: "555 0100", expense: "Dinner",
            outstanding: Money(cents: 30_00)
        ))
        #expect(reminder.original == (try fixture.expectation(of: alex, on: dinner)).persistentModelID)
    }

    @Test func aReminderArrivesAtNineOnItsDay() async throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        dinner.note = "Dinner"
        let owed = try fixture.expectation(of: alex, on: dinner)
        try owed.setReminder(day(2026, 10, 15))
        let scheduler = RecordingReminderScheduler<ExpectedReimbursementReminder>()

        try await fixture.owesMe().reschedule(
            at: moment(today, at: 8), calendar: .utcGregorian, after: [], using: scheduler
        )

        #expect(scheduler.calls == [
            .requestPermission,
            .replacePending([
                ExpectedReimbursementReminder(
                    original: owed.persistentModelID, day: day(2026, 10, 15), person: alex.persistentModelID,
                    personName: "Alex", phone: nil, expense: "Dinner", outstanding: Money(cents: 30_00),
                    arrival: .onItsDay
                ),
            ]),
        ])
    }

    @Test func aReminderForTodayArrivesRightAwayWhenItIsNewAfterNine() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(on: day(2026, 10, 5), owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        #expect(owed.reminderDay == today)
        let list = try fixture.owesMe()

        let newAfterNine = list.reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: [])
        let arrivedAlready = list.reminders(at: moment(today, at: 14), calendar: .utcGregorian, after: list.reminders(from: today))

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
        try lunch.delete(.onlySelected)
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
        let loanRemindersBefore = DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today)

        try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])

        #expect(DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).reminders(from: today) == loanRemindersBefore)
        #expect(loanRemindersBefore.count == 1)
        #expect(DebtsAndLoans(try context.fetch(DebtsAndLoans.records)).due(on: today).isEmpty)
        #expect(ExpectedReimbursementReminder.identifierPrefix != DebtReminder.identifierPrefix)
        #expect(ExpectedReimbursementReminder.identifierPrefix != EstimateReminder.identifierPrefix)
    }
}
