import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Report's Income, Spent and Net income for a period and a wallet selection. They count as Home's Month graph
/// counts them, except that the Report counts the selection it is given rather than always the Total.
@MainActor
struct ReportTotalsTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// The totals of `period` (this month unless another is given) for `selection`, as of today.
    private func totals(_ selection: WalletSelection = .total, in period: Period? = nil) throws -> PeriodTotals {
        try PeriodTotals(
            of: store.transactions(), in: selection, period: period ?? .month(CalendarMonth(today)), today: today,
            otherIncome: store.otherIncome()
        )
    }

    private func addSavings() -> Wallet {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        return savings
    }

    // MARK: What counts

    @Test func incomeSpentAndNetIncomeOfTheMonthSoFar() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))

        let october = try totals()
        #expect(october.income == Money(cents: 1_500_00))
        #expect(october.spent == Money(cents: 40_00))
        #expect(october.netIncome == Money(cents: 1_460_00))
    }

    @Test func aRefundLowersSpent() throws {
        try store.record(-80_00, "Clothing", on: day(2026, 10, 2))
        try store.record(30_00, "Clothing", on: day(2026, 10, 6))

        #expect(try totals().spent == Money(cents: 50_00))
    }

    @Test func withTotalTheMonthEqualsHomesMonthGraphHeadlines() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        try store.record(-80_00, "Clothing", on: day(2026, 10, 2))
        try store.record(30_00, "Clothing", on: day(2026, 10, 6))

        let october = try totals()
        #expect(october.spent == (try store.graph(.spent).headline))
        #expect(october.income == (try store.graph(.income).headline))
    }

    /// Only the days of the period count: the last day of the month before and anything after today don't.
    @Test func onlyTheDaysOfThePeriodUpToTodayCount() throws {
        try store.record(-60_00, "Café", on: day(2026, 9, 30))
        try store.record(-70_00, "Café", on: day(2026, 10, 1))
        try store.record(-80_00, "Café", on: day(2026, 10, 12))
        try store.record(-90_00, "Café", on: day(2026, 10, 13))

        #expect(try totals().spent == Money(cents: 150_00))
    }

    @Test func aWeekCountsOnlyItsOwnDays() throws {
        try store.record(-10_00, "Café", on: day(2026, 10, 4))
        try store.record(-20_00, "Café", on: day(2026, 10, 5))
        try store.record(-30_00, "Café", on: day(2026, 10, 11))
        try store.record(-40_00, "Café", on: day(2026, 10, 12))

        let week = Period.week(startingOn: day(2026, 10, 5))
        #expect(try totals(in: week).spent == Money(cents: 50_00))
    }

    @Test func aWalletCountsOnlyItsOwnTransactions() throws {
        let savings = addSavings()
        try store.record(-25_00, "Café", on: day(2026, 10, 4), in: savings)
        try store.record(-40_00, "Café", on: day(2026, 10, 3))

        #expect(try totals(.wallet(checking)).spent == Money(cents: 40_00))
        #expect(try totals(.wallet(savings)).spent == Money(cents: 25_00))
        #expect(try totals(.total).spent == Money(cents: 65_00))
    }

    /// A transfer's halves are filed under an Expense and an Income category, and neither is excluded from report.
    @Test func transfersCountInNeither() throws {
        let savings = addSavings()
        var draft = TransferDraft(day: day(2026, 10, 4))
        draft.from = checking
        draft.to = savings
        draft.amount = Money(cents: 250_00)
        try Transfer.create(draft, in: context)

        #expect(try totals() == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
        #expect(try totals(.wallet(savings)) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
    }

    @Test func aTransactionExcludedFromReportCountsInNeither() throws {
        let coffee = try store.record(-40_00, "Café", on: day(2026, 10, 3))
        let salary = try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        coffee.isExcludedFromReport = true
        salary.isExcludedFromReport = true

        #expect(try totals() == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
    }

    /// A Loan forgiven in October is spent in October, on the day it was forgiven, and a Debt forgiven is income.
    @Test func forgivenLoansAndDebtsCountOnTheDayTheyWereForgiven() throws {
        let loan = try store.lendOrBorrow(.loan, 250_00, on: day(2026, 9, 20))
        let debt = try store.lendOrBorrow(.debt, 80_00, on: day(2026, 9, 25))
        try store.forgive(loan, on: day(2026, 10, 5))
        try store.forgive(debt, on: day(2026, 10, 7))

        let october = try totals()
        #expect(october.spent == Money(cents: 250_00))
        #expect(october.income == Money(cents: 80_00))
        #expect(try totals(in: .month(CalendarMonth(year: 2026, month: 9))).spent == Money(cents: 0))
    }

    @Test func aWalletsForgivenLoanCountsOnlyWhenItIsSelected() throws {
        let savings = addSavings()
        let loan = try store.lendOrBorrow(.loan, 250_00, on: day(2026, 9, 20))
        loan.wallet = savings
        try store.forgive(loan, on: day(2026, 10, 5))

        #expect(try totals(.wallet(checking)).spent == Money(cents: 0))
        #expect(try totals(.wallet(savings)).spent == Money(cents: 250_00))
    }
}
