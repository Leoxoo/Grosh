import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Record payment on an Expected reimbursement paid into the Expense's own wallet: a Reimbursement on the Expense, netted
/// into its wallet on its own day, as the glossary defines. Partial payments leave the rest outstanding, an expectation
/// with an amount closes itself when covered, an open amount stays open until closed by hand, and paying more than
/// expected follows the Reimbursement excess rule.
@MainActor
struct ExpectedReimbursementPaymentTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.checking }
    private var today: CalendarDay { fixture.today }
    private let dinnerDay = day(2026, 10, 3)

    init() throws {
        fixture = try ExpectationFixture()
    }

    @Test func recordPaymentAddsAReimbursementToTheExpenseWithItsAmountDayAndNote() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        let recorded = try fixture.pay(10_00, on: owed, day: day(2026, 10, 8), note: "Venmo")

        guard case .onExpense(let entry) = recorded else {
            Issue.record("Expected a Reimbursement on the Expense.")
            return
        }
        #expect(dinner.orderedReimbursements == [entry])
        #expect(entry.amountCents == 10_00)
        #expect(entry.day == day(2026, 10, 8))
        #expect(entry.note == "Venmo")
        #expect(entry.expectation === owed)
        #expect(owed.payments.map(\.amount) == [Money(cents: 10_00)])
    }

    @Test func thePaymentIsNettedIntoTheExpensesWalletOnTheExpensesDay() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let before = try fixture.totals()
        #expect(before.spent == Money(cents: 60_00))

        try fixture.pay(20_00, on: fixture.expectation(of: alex, on: dinner), day: today)

        #expect(dinner.netCents == -40_00)
        #expect(checking.balance(asOf: day(2026, 10, 3)) == Money(cents: -40_00))
        #expect([dinner].net == Money(cents: -40_00))
        #expect(try fixture.totals().spent == Money(cents: 40_00))
        #expect(try fixture.store.graph(.spent).headline == Money(cents: 40_00))
        let entries = try context.fetch(Transaction.notDeleted).map(LedgerEntry.init)
        #expect(WalletBalances(entries, asOf: today).balance(of: checking) == Money(cents: -40_00))
    }

    @Test func aPartialPaymentLeavesTheRestOutstanding() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try fixture.pay(10_00, on: owed)

        #expect(owed.isOpen)
        #expect(owed.paid == Money(cents: 10_00))
        #expect(owed.outstanding == Money(cents: 20_00))
        #expect(try fixture.owesMe().open == [owed])
        #expect(try fixture.owesMe().totals.outstanding == [Money(cents: 20_00)])
    }

    @Test func aPaymentCoveringTheAmountClosesTheExpectationItself() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try fixture.pay(10_00, on: owed)
        try fixture.pay(20_00, on: owed)

        #expect(owed.status == .paidBack)
        #expect(!owed.isOpen)
        #expect(owed.outstanding == Money(cents: 0))
        #expect(try fixture.owesMe().open.isEmpty)
        #expect(try fixture.owesMe().settled == [owed])
    }

    @Test func payingExactlyWhatIsOutstandingIsOneTap() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        let draft = ExpectationPaymentDraft(paying: owed, on: today)

        #expect(draft.amount == Money(cents: 30_00))
        #expect(draft.wallet === checking)
        try owed.recordPayment(draft, in: context)

        #expect(owed.status == .paidBack)
    }

    @Test func payingMoreThanExpectedIsAcceptedAndTheExcessCountsAsOtherIncome() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(40_00, owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try fixture.pay(50_00, on: owed)

        #expect(owed.status == .paidBack)
        #expect(owed.outstanding == Money(cents: 0))
        #expect(dinner.netCents == 10_00)
        let counted = try #require(dinner.countedAmount(otherIncome: fixture.store.otherIncome()))
        #expect(counted.side == .income)
        #expect(counted.amount == Money(cents: 10_00))
        #expect(counted.category.name == "Other Income")
        #expect(try fixture.totals() == PeriodTotals(income: Money(cents: 10_00), spent: Money(cents: 0)))
    }

    @Test func anOpenAmountExpectationStaysOpenAfterAPayment() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, nil)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        try fixture.pay(25_00, on: owed)

        #expect(owed.isOpen)
        #expect(owed.hasOpenAmount)
        #expect(owed.paid == Money(cents: 25_00))
        #expect(owed.outstanding == nil)
        #expect(dinner.netCents == -35_00)
    }

    @Test func anOpenAmountExpectationIsClosedByHandAndCanBeReopened() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, nil)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        try fixture.pay(25_00, on: owed)

        try owed.close(on: today)

        #expect(owed.status == .closed)
        #expect(owed.closedDay == today)
        #expect(!owed.isOpen)
        #expect(try fixture.owesMe().settled == [owed])
        #expect(try fixture.owesMe().totals.openAmountCount == 0)

        try owed.reopen()

        #expect(owed.isOpen)
        #expect(try fixture.owesMe().totals.openAmountCount == 1)
    }

    @Test func onlyAnOpenAmountIsClosedByHand() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))

        #expect(throws: ExpectedReimbursementRuleError.hasAnAmount) {
            try owed.close(on: today)
        }
        #expect(throws: ExpectedReimbursementRuleError.notClosed) {
            try owed.reopen()
        }
    }

    @Test func aSettledExpectationTakesNoMorePayments() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))
        try fixture.pay(30_00, on: owed)

        #expect(throws: ExpectedReimbursementRuleError.notOpen) {
            try fixture.pay(5_00, on: owed)
        }
        #expect(owed.payments.count == 1)
    }

    @Test func aPaymentNeedsAnAmountAboveZero() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, nil)]))
        let draft = ExpectationPaymentDraft(paying: owed, on: today)

        #expect(draft.amount == Money(cents: 0))
        #expect(throws: ReimbursementRuleError.missingAmount) {
            try owed.recordPayment(draft, in: context)
        }
    }

    @Test func theDetailShowsTheExpectationsPaymentsEarliestFirst() throws {
        let alex = try fixture.person("Alex")
        let sam = try fixture.person("Sam")
        let dinner = try fixture.dinner(owing: [(alex, 30_00), (sam, 20_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        try fixture.pay(5_00, on: owed, day: day(2026, 10, 9))
        try fixture.pay(10_00, on: owed, day: day(2026, 10, 5), note: "Cash")
        try fixture.pay(20_00, on: fixture.expectation(of: sam, on: dinner), day: today)

        #expect(owed.payments.map(\.amount) == [Money(cents: 10_00), Money(cents: 5_00)])
        #expect(owed.payments.map(\.day) == [day(2026, 10, 5), day(2026, 10, 9)])
        #expect(owed.payments.first?.note == "Cash")
        #expect(owed.payments.allSatisfy { !$0.isElsewhere })
    }

    @Test func deletingAPaymentReopensTheExpectation() throws {
        let alex = try fixture.person("Alex")
        let owed = try fixture.expectation(of: alex, on: fixture.dinner(owing: [(alex, 30_00)]))
        guard case .onExpense(let entry) = try fixture.pay(30_00, on: owed) else {
            Issue.record("Expected a Reimbursement on the Expense.")
            return
        }
        #expect(owed.status == .paidBack)

        try entry.delete()

        #expect(owed.isOpen)
        #expect(owed.outstanding == Money(cents: 30_00))
    }
}
