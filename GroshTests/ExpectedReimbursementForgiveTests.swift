import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Forgive on an Expected reimbursement: the money won't come back. It is marked Forgiven on a day with an optional note
/// and counts as settled, and can be un-forgiven. It adds no transaction and, as the expectation never counted in any
/// balance or report, changes none (ADR-0004, ADR-0010).
@MainActor
@Suite(.namedInTheLog)
struct ExpectedReimbursementForgiveTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var today: CalendarDay { fixture.today }

    init() throws {
        fixture = try ExpectationFixture()
    }

    @Test func forgivingMarksTheExpectationForgivenOnTheDayWithItsNote() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))

        try owed.forgive(on: day(2026, 10, 11), note: "  Covered his half  ")

        #expect(owed.status == .forgiven)
        #expect(owed.forgivenDay == day(2026, 10, 11))
        #expect(owed.forgivenNote == "Covered his half")
        #expect(!owed.isOpen)
        #expect(owed.outstanding == Money(cents: 0))
    }

    @Test func aForgivenExpectationIsListedAsSettled() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))

        try owed.forgive(on: today)

        let listed = try fixture.owesMe()
        #expect(listed.open.isEmpty)
        #expect(listed.settled == [owed])
        #expect(listed.totals.outstanding.isEmpty)
    }

    @Test func anOpenAmountExpectationCanBeForgivenToo() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, nil)]))

        try owed.forgive(on: today)

        #expect(owed.status == .forgiven)
        #expect(try fixture.owesMe().totals.openAmountCount == 0)
    }

    @Test func forgivingChangesNoBalanceReportOrNetAndAddsNoTransaction() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let balance = fixture.checking.balance(asOf: today)
        let totals = try fixture.totals()
        let graph = try fixture.store.graph(.spent).headline
        let transactionCount = try context.fetchCount(FetchDescriptor<Transaction>())

        try fixture.expectation(of: alex, on: dinner).forgive(on: today, note: "Gift")

        #expect(fixture.checking.balance(asOf: today) == balance)
        #expect(try fixture.totals() == totals)
        #expect(try fixture.store.graph(.spent).headline == graph)
        #expect(dinner.netCents == -60_00)
        #expect(dinner.reimbursedCents == 0)
        #expect(dinner.orderedReimbursements.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == transactionCount)
    }

    @Test func forgivingTheRestAfterAPartialPaymentSettlesIt() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))
        try fixture.pay(10_00, on: owed)

        try owed.forgive(on: today)

        #expect(owed.status == .forgiven)
        #expect(owed.paid == Money(cents: 10_00))
    }

    @Test func aForgivenExpectationCanBeUnforgivenAndIsOpenAgain() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))
        try owed.forgive(on: today, note: "Gift")

        try owed.unforgive()

        #expect(owed.isOpen)
        #expect(owed.forgivenDay == nil)
        #expect(owed.forgivenNote.isEmpty)
        #expect(owed.outstanding == Money(cents: 30_00))
        #expect(try fixture.owesMe().open == [owed])
    }

    @Test func onlyAnOpenExpectationIsForgivenAndOnlyAForgivenOneUnforgiven() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))

        #expect(throws: ExpectedReimbursementRuleError.notForgiven) {
            try owed.unforgive()
        }
        try owed.forgive(on: today)
        #expect(throws: ExpectedReimbursementRuleError.notOpen) {
            try owed.forgive(on: today)
        }
    }

    @Test func anExpectationPaidBackInFullIsNotForgiven() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))
        try fixture.pay(30_00, on: owed)

        #expect(throws: ExpectedReimbursementRuleError.notOpen) {
            try owed.forgive(on: today)
        }
    }

    @Test func forgivingWithdrawsTheReminderAndUnforgivingRestoresIt() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(on: day(2026, 10, 8), owing: [(alex, 30_00)]))
        #expect(try fixture.owesMe().reminders(from: today).count == 1)

        try owed.forgive(on: today)
        #expect(try fixture.owesMe().reminders(from: today).isEmpty)
        #expect(try fixture.owesMe().due(on: day(2026, 10, 30)).isEmpty)

        try owed.unforgive()
        #expect(try fixture.owesMe().reminders(from: today).count == 1)
        #expect(owed.reminderDay == day(2026, 10, 15))
    }
}
