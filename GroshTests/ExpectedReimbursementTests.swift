import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Owes me on an Expense (ADR-0010): each person chosen in With can owe part of it, with an optional amount. It is listed
/// in Debts & Loans, never changes a balance or a report, goes to Recently Deleted and back with its Expense, and an edit
/// that would break it is refused.
@MainActor
@Suite(.namedInTheLog)
struct ExpectedReimbursementTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var today: CalendarDay { fixture.today }
    private let deletedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        fixture = try ExpectationFixture()
    }

    // MARK: Creating

    @Test func eachPersonChosenOnAnExpenseCanOweAPartOfItWithAnAmount() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")

        let dinner = try fixture.dinner(owing: [(alex, 30_00), (sam, 15_00)])

        #expect(dinner.orderedExpectations.count == 2)
        let owed = try fixture.expectation(of: alex, on: dinner)
        #expect(owed.expected == Money(cents: 30_00))
        #expect(owed.outstanding == Money(cents: 30_00))
        #expect(owed.isOpen)
        #expect(try fixture.expectation(of: sam, on: dinner).expected == Money(cents: 15_00))
    }

    @Test func leavingTheAmountBlankMakesTheExpectationOpen() throws {
        let alex = try fixture.person("Alex")

        let dinner = try fixture.dinner(owing: [(alex, nil)])

        let owed = try fixture.expectation(of: alex, on: dinner)
        #expect(owed.hasOpenAmount)
        #expect(owed.expected == nil)
        #expect(owed.outstanding == nil)
        #expect(owed.isOpen)
    }

    @Test func onlyAnExpenseOffersOwesMe() throws {
        var income = TransactionDraft(type: .income, day: today)
        income.category = try fixture.store.category("Salary", .income)
        var expense = TransactionDraft(type: .expense, day: today)
        expense.category = try fixture.store.category("Restaurants")

        #expect(!income.offersOwesMe)
        #expect(expense.offersOwesMe)
    }

    @Test func aPersonTakenOutOfWithLosesTheNewOwesMeTheyHad() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        var draft = TransactionDraft(type: .expense, day: today)
        draft.people = [alex, sam]
        draft.addOwes(alex)
        draft.addOwes(sam)

        draft.people = [sam]

        #expect(draft.owes.map(\.person) == [sam])
    }

    // MARK: Listed in Debts & Loans

    @Test func theExpectationIsListedWithItsPersonItsExpenseAndWhatIsOutstanding() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])

        let listed = try fixture.owesMe()

        let owed = try #require(listed.open.first)
        #expect(listed.open.count == 1)
        #expect(listed.settled.isEmpty)
        #expect(owed.person === alex)
        #expect(owed.expense === dinner)
        #expect(owed.outstanding == Money(cents: 30_00))
    }

    @Test func openAmountExpectationsAreLeftOutOfTotalsAndFlagged() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        try fixture.dinner(owing: [(alex, 30_00), (sam, nil)])
        try fixture.dinner(20_00, owing: [(alex, 5_00)])

        let totals = try fixture.owesMe().totals

        #expect(totals.outstanding == [Money(cents: 35_00)])
        #expect(totals.openAmountCount == 1)
        #expect(totals.summary == "\(Money(cents: 35_00).formatted()) · +1 open")
    }

    @Test func theExpectationsOfEachPersonAreGroupedForShowByPeople() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        try fixture.dinner(owing: [(alex, 30_00), (sam, nil)])
        try fixture.dinner(20_00, owing: [(alex, 5_00)])

        let people = try fixture.owesMe().byPerson

        #expect(people.map(\.person) == [alex, sam])
        #expect(people[0].expectations.count == 2)
        let alexOwes = ExpectationTotals(people[0].expectations)
        #expect(alexOwes.outstanding == [Money(cents: 35_00)])
        #expect(alexOwes.openAmountCount == 0)
        let samOwes = ExpectationTotals(people[1].expectations)
        #expect(samOwes.outstanding.isEmpty)
        #expect(samOwes.openAmountCount == 1)
    }

    // MARK: No accounting effect

    @Test func owesMeChangesNoBalanceListTotalOrReport() throws {
        let alex = try fixture.person("Alex")
        let plain = try fixture.dinner()
        let balanceBefore = fixture.checking.balance(asOf: today)
        let totalsBefore = try fixture.totals()
        let graphBefore = try fixture.store.graph(.spent).headline

        var draft = TransactionDraft(editing: plain)
        draft.people = [alex]
        draft.addOwes(alex)
        try plain.update(with: draft)

        #expect(fixture.checking.balance(asOf: today) == balanceBefore)
        #expect(plain.netCents == -60_00)
        #expect([plain].net == Money(cents: -60_00))
        #expect(try fixture.totals() == totalsBefore)
        #expect(try fixture.store.graph(.spent).headline == graphBefore)
        #expect(plain.countedAmount(otherIncome: try fixture.store.otherIncome())?.amount == Money(cents: 60_00))
    }

    @Test func editingAndRemovingAnExpectationChangesNoBalanceOrReport() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let balanceBefore = fixture.checking.balance(asOf: today)
        let totalsBefore = try fixture.totals()

        var draft = TransactionDraft(editing: dinner)
        draft.owes[0].amount = Money(cents: 10_00)
        try dinner.update(with: draft)
        #expect(try fixture.expectation(of: alex, on: dinner).expected == Money(cents: 10_00))
        #expect(fixture.checking.balance(asOf: today) == balanceBefore)
        #expect(try fixture.totals() == totalsBefore)

        var removing = TransactionDraft(editing: dinner)
        removing.removeOwes(alex)
        try dinner.update(with: removing)
        #expect(dinner.orderedExpectations.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<ExpectedReimbursement>()) == 0)
        #expect(fixture.checking.balance(asOf: today) == balanceBefore)
        #expect(try fixture.totals() == totalsBefore)
    }

    // MARK: Recently Deleted

    @Test func deletingTheExpenseSendsItsExpectationsToRecentlyDeletedWithIt() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])

        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        #expect(try fixture.owesMe().open.isEmpty)
        #expect(try fixture.owesMe().totals.outstanding.isEmpty)
        #expect(dinner.orderedExpectations.count == 1)
        #expect(try RecentlyDeleted(in: context).transactions == [dinner])
    }

    @Test func restoringTheExpenseRestoresItsExpectations() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        try dinner.restore()

        let listed = try fixture.owesMe()
        #expect(listed.open.map(\.persistentModelID) == dinner.orderedExpectations.map(\.persistentModelID))
        #expect(listed.open.first?.outstanding == Money(cents: 30_00))
    }

    @Test func deletingTheExpenseForeverRemovesItsExpectationsButNotThePerson() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        try dinner.deleteForever(in: context)

        #expect(try context.fetchCount(FetchDescriptor<ExpectedReimbursement>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Person>()) == 1)
        #expect(alex.expectations?.isEmpty == true)
    }

    // MARK: The edit guard

    @Test func anExpenseWithOwesMeCantBecomeIncome() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        var draft = TransactionDraft(editing: dinner)
        draft.type = .income
        draft.category = try fixture.store.category("Salary", .income)

        #expect(throws: ExpectedReimbursementRuleError.notAnExpense) {
            try dinner.update(with: draft)
        }
        #expect(dinner.amountCents == -60_00)
        #expect(dinner.orderedExpectations.count == 1)
    }

    @Test func aPersonWhoOwesCantBeTakenOutOfWith() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        var draft = TransactionDraft(editing: dinner)
        draft.people = []

        #expect(throws: ExpectedReimbursementRuleError.personNotInWith("Alex")) {
            try dinner.update(with: draft)
        }
        #expect(dinner.orderedPeople == [alex])
    }

    @Test func anExpenseCantCostLessThanWhatIsOwedOnIt() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let dinner = try fixture.dinner(owing: [(alex, 30_00), (sam, 20_00)])
        var cheaper = TransactionDraft(editing: dinner)
        cheaper.amount = Money(cents: 40_00)

        #expect(throws: ExpectedReimbursementRuleError.amountAboveExpense) {
            try dinner.update(with: cheaper)
        }
        #expect(dinner.amountCents == -60_00)
    }

    @Test func noOneCanOweMoreThanTheExpenseCost() throws {
        let alex = try fixture.person("Alex")
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = fixture.checking
        draft.amount = Money(cents: 60_00)
        draft.category = try fixture.store.category("Restaurants")
        draft.people = [alex]
        draft.addOwes(alex)
        draft.owes[0].amount = Money(cents: 70_00)

        #expect(throws: ExpectedReimbursementRuleError.amountAboveExpense) {
            try Transaction.create(draft, in: context)
        }
        draft.owes[0].amount = Money(cents: 0)
        #expect(throws: ExpectedReimbursementRuleError.invalidAmount) {
            try Transaction.create(draft, in: context)
        }
    }

    @Test func anExpectationWithPaymentsCantBeRemoved() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        try fixture.pay(10_00, on: fixture.expectation(of: alex, on: dinner))

        var draft = TransactionDraft(editing: dinner)
        draft.removeOwes(alex)

        #expect(draft.owes.count == 1)
        draft = TransactionDraft(editing: dinner)
        draft.owes = []
        #expect(throws: ExpectedReimbursementRuleError.hasPayments("Alex")) {
            try dinner.update(with: draft)
        }
        #expect(dinner.orderedExpectations.count == 1)
    }
}
