import Foundation
import SwiftData
import Testing
@testable import Grosh

/// What an Expense with Reimbursements counts on the Month graph and the Report: its net as Spent under its own category
/// while the net is below zero, nothing at zero, and above zero the extra as Income under Other Income, all on the
/// Expense's own day.
@MainActor
@Suite(.namedInTheLog)
struct ReimbursementCountingTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A dinner of $60 on the 3rd, the Expense most tests pay back.
    private func dinner() throws -> Transaction {
        try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
    }

    @discardableResult
    private func payBack(_ cents: Int, on paidOn: CalendarDay? = nil, to expense: Transaction) throws -> Reimbursement {
        try Reimbursement.add(ReimbursementDraft(amount: Money(cents: cents), day: paidOn ?? today), to: expense, in: context)
    }

    /// The totals of this month for `selection`, as the Report counts them.
    private func totals(_ selection: WalletSelection = .total) throws -> PeriodTotals {
        try PeriodTotals(
            of: store.transactions(), in: selection, period: .month(CalendarMonth(today)), today: today,
            otherIncome: store.otherIncome()
        )
    }

    // MARK: What an Expense counts

    @Test func aPartiallyReimbursedExpenseCountsItsNetAsSpentUnderItsOwnCategoryOnItsOwnDay() throws {
        let dinner = try dinner()
        try payBack(20_00, on: day(2026, 10, 8), to: dinner)

        let counted = try #require(dinner.countedAmount(otherIncome: store.otherIncome()))

        #expect(counted.side == .spent)
        #expect(counted.amount == Money(cents: 40_00))
        #expect(counted.category.name == "Restaurants")
        #expect(counted.day == day(2026, 10, 3))
    }

    @Test func anExactlyReimbursedExpenseCountsNothing() throws {
        let dinner = try dinner()
        try payBack(60_00, to: dinner)

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome()) == nil)
        #expect(try totals() == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
    }

    @Test func anOverReimbursedExpenseCountsTheExtraAsIncomeUnderOtherIncomeOnItsOwnDay() throws {
        let dinner = try dinner()
        try payBack(100_00, on: day(2026, 10, 8), to: dinner)

        let counted = try #require(dinner.countedAmount(otherIncome: store.otherIncome()))

        #expect(counted.side == .income)
        #expect(counted.amount == Money(cents: 40_00))
        #expect(counted.category.lockedRole == .otherIncome)
        #expect(counted.day == day(2026, 10, 3))
        #expect(try totals() == PeriodTotals(income: Money(cents: 40_00), spent: Money(cents: 0)))
    }

    @Test func anOverReimbursedExpenseFilesItsExtraUnderTheOtherIncomeTheReportHandsIt() throws {
        let dinner = try dinner()
        try payBack(100_00, to: dinner)
        let readOnce = try store.category("Tips", .income)

        #expect(dinner.countedAmount(otherIncome: readOnce)?.category == readOnce)
    }

    @Test func severalReimbursementsCountTogether() throws {
        let dinner = try dinner()
        try payBack(20_00, to: dinner)
        try payBack(15_00, to: dinner)

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: 25_00))
        #expect(try totals().spent == Money(cents: 25_00))

        try payBack(30_00, to: dinner)

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.side == .income)
        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: 5_00))
    }

    @Test func removingAReimbursementCountsTheExpenseAgain() throws {
        let dinner = try dinner()
        let entry = try payBack(60_00, to: dinner)
        #expect(dinner.countedAmount(otherIncome: try store.otherIncome()) == nil)

        try entry.delete()

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.side == .spent)
        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: 60_00))
    }

    @Test func anExpenseWithoutReimbursementsCountsAsBefore() throws {
        let dinner = try dinner()
        let refund = try store.record(30_00, "Clothing", on: day(2026, 10, 6))

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: 60_00))
        #expect(refund.countedAmount(otherIncome: try store.otherIncome())?.side == .spent)
        #expect(refund.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: -30_00))
    }

    @Test func aReimbursedExpenseExcludedFromReportCountsInNeither() throws {
        let dinner = try dinner()
        try payBack(100_00, to: dinner)
        dinner.isExcludedFromReport = true

        #expect(dinner.countedAmount(otherIncome: try store.otherIncome()) == nil)
    }

    @Test func whenTheMoneyWasPaidBackDoesntMoveWhatCountsToAnotherPeriod() throws {
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 9, 30))
        try payBack(20_00, on: day(2026, 10, 5), to: dinner)

        let september = Period.month(CalendarMonth(year: 2026, month: 9))
        #expect(try PeriodTotals(
            of: store.transactions(), in: .total, period: september, today: today, otherIncome: store.otherIncome()
        ).spent == Money(cents: 40_00))
        #expect(try totals().spent == Money(cents: 0))
    }

    // MARK: Where it counts

    @Test func aWalletCountsTheNetOfItsOwnExpensesOnly() throws {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        let dinner = try dinner()
        let lunch = try store.record(-30_00, "Restaurants", on: day(2026, 10, 4), in: savings)
        try payBack(20_00, to: dinner)
        try payBack(30_00, to: lunch)

        #expect(try totals(.wallet(store.checking)).spent == Money(cents: 40_00))
        #expect(try totals(.wallet(savings)) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
        #expect(try totals().spent == Money(cents: 40_00))
    }

    @Test func theReportAndTheMonthGraphCountTheNet() throws {
        let dinner = try dinner()
        try store.record(-10_00, "Café", on: day(2026, 10, 4))
        try payBack(20_00, to: dinner)

        let october = try totals()
        #expect(october.spent == Money(cents: 50_00))
        #expect(october.netIncome == Money(cents: -50_00))
        #expect(try store.graph(.spent).headline == Money(cents: 50_00))
    }

    @Test func anOverReimbursedExpenseAddsToTheMonthGraphsIncome() throws {
        let dinner = try dinner()
        try payBack(100_00, to: dinner)

        #expect(try store.graph(.income).headline == Money(cents: 40_00))
        #expect(try store.graph(.spent).headline == Money(cents: 0))
        #expect(try totals().netIncome == Money(cents: 40_00))
    }

    @Test func theCategoryReportFilesTheNetUnderTheExpensesCategoryAndTheExtraUnderOtherIncome() throws {
        let dinner = try dinner()
        let lunch = try store.record(-30_00, "Café", on: day(2026, 10, 4))
        try payBack(20_00, to: dinner)
        try payBack(50_00, to: lunch)

        let counted = try store.transactions().counted(
            in: .total, during: .month(CalendarMonth(today)), today: today, otherIncome: store.otherIncome()
        )
        let spent = CategoryBreakdown(side: .spent, of: counted)
        let income = CategoryBreakdown(side: .income, of: counted)

        #expect(spent.categories.map(\.category.name) == ["Food & Beverage"])
        #expect(spent.total == Money(cents: 40_00))
        #expect(income.categories.map(\.category.name) == ["Other Income"])
        #expect(income.total == Money(cents: 20_00))
    }

    @Test func aBreakdownRowListsTheExpenseWhereItsNetCounts() throws {
        let dinner = try dinner()
        try payBack(100_00, to: dinner)
        let otherIncome = try context.lockedCategory(.otherIncome)
        let days = DayRange(first: day(2026, 10, 1), last: today)

        let income = CategoryTransactions(
            parent: otherIncome, side: .income, of: try store.transactions(), in: .total, days: days,
            otherIncome: otherIncome
        )
        let spent = CategoryTransactions(
            parent: try store.category("Food & Beverage"), side: .spent, of: try store.transactions(), in: .total, days: days,
            otherIncome: otherIncome
        )

        #expect(income.transactions == [dinner])
        #expect(income.total == Money(cents: 40_00))
        #expect(spent.transactions.isEmpty)
    }

    @Test func aStepListsTheNetItCounts() throws {
        let dinner = try dinner()
        try payBack(20_00, to: dinner)

        let step = PeriodTransactions(
            side: nil, of: try store.transactions(), in: .total, days: DayRange(first: day(2026, 10, 3), last: day(2026, 10, 3)),
            otherIncome: try store.otherIncome()
        )

        #expect(step.transactions == [dinner])
        #expect(step.total == Money(cents: -40_00))
    }

    @Test func theDailyAverageIsOfTheNet() throws {
        let dinner = try dinner()
        try payBack(20_00, to: dinner)
        let days = DayRange(first: day(2026, 10, 1), last: day(2026, 10, 10))

        #expect(DailyAverage.of(try totals().spent, over: days) == Money(cents: 4_00))
    }
}
