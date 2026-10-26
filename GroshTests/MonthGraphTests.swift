import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Home's Spent and Income cards: what counts toward each, the running total of the month so far, and the day the
/// marker is on.
@MainActor
@Suite(.namedInTheLog)
struct MonthGraphTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A Loan (you lent) or Debt (you borrowed) of `cents`, saved through a draft made as Debt/Loan from the start. It
    /// skips the Add sheet's switch to the Debt/Loan tab, which is what turns Exclude from report on, so it is left in
    /// the report and only its category keeps it off the cards.
    @discardableResult
    private func record(_ role: LockedRole, _ cents: Int, on day: CalendarDay) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: day)
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.withName = "Pasha"
        return try Transaction.create(draft, in: context)
    }

    /// Records a payment of `cents` on `loanOrDebt` through Record payment's draft.
    @discardableResult
    private func pay(_ cents: Int, on loanOrDebt: Transaction) throws -> Transaction {
        var draft = try DebtPaymentDraft(settling: loanOrDebt, on: day(2026, 10, 8), in: context)
        draft.amount = Money(cents: cents)
        return try DebtPayment.record(draft, in: context).payment
    }

    /// Forgives what is outstanding on `loanOrDebt` on `day`, under Other Expense for a Loan or Other Income for a Debt.
    private func forgive(_ loanOrDebt: Transaction, on day: CalendarDay) throws {
        try Forgiveness.record(ForgiveDraft(forgiving: loanOrDebt, on: day, in: context), in: context)
    }

    // MARK: What counts

    @Test func anExpenseCountsAsSpentAndAnIncomeAsIncome() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))

        #expect(try store.graph(.spent).headline == Money(cents: 40_00))
        #expect(try store.graph(.income).headline == Money(cents: 1_500_00))
    }

    @Test func aRefundLowersSpent() throws {
        try store.record(-80_00, "Clothing", on: day(2026, 10, 2))
        try store.record(30_00, "Clothing", on: day(2026, 10, 6))

        #expect(try store.graph(.spent).headline == Money(cents: 50_00))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    @Test func aTransactionExcludedFromReportCountsInNeither() throws {
        let coffee = try store.record(-40_00, "Café", on: day(2026, 10, 3))
        let salary = try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        coffee.isExcludedFromReport = true
        salary.isExcludedFromReport = true

        #expect(try store.graph(.spent).headline == Money(cents: 0))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    /// A transfer's halves are filed under an Expense and an Income category, and neither is excluded from report.
    @Test func aTransferCountsInNeither() throws {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        var draft = TransferDraft(day: day(2026, 10, 4))
        draft.from = checking
        draft.to = savings
        draft.amount = Money(cents: 250_00)
        try Transfer.create(draft, in: context)

        #expect(try store.graph(.spent).headline == Money(cents: 0))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    /// A new wallet's Starting balance is excluded from report; one an import brings may not be. Neither counts.
    @Test func aStartingBalanceCountsInNeither() throws {
        try Wallet.create(name: "Cash", startingBalance: Money(cents: 300_00), on: day(2026, 10, 1), in: context)
        try store.record(500_00, "Starting balance", .system, on: day(2026, 10, 2))

        #expect(try store.graph(.income).headline == Money(cents: 0))
        #expect(try store.graph(.spent).headline == Money(cents: 0))
    }

    /// Payments are recorded excluded from report; an import may leave them in, as it may a Loan or Debt.
    @Test func loansDebtsAndTheirPaymentsCountInNeither() throws {
        let loan = try record(.loan, 100_00, on: day(2026, 10, 2))
        let debt = try record(.debt, 250_00, on: day(2026, 10, 3))
        let collection = try pay(40_00, on: loan)
        let repayment = try pay(50_00, on: debt)
        collection.isExcludedFromReport = false
        repayment.isExcludedFromReport = false

        #expect(try store.graph(.spent).headline == Money(cents: 0))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    /// Lent and borrowed last month, and excluded from report as the Add sheet would save them: only what is forgiven
    /// counts, whatever their own flag says.
    @Test func aForgivenLoanCountsAsSpentAndAForgivenDebtAsIncomeOnTheDayTheyWereForgiven() throws {
        let loan = try record(.loan, 100_00, on: day(2026, 9, 20))
        let debt = try record(.debt, 250_00, on: day(2026, 9, 25))
        loan.isExcludedFromReport = true
        debt.isExcludedFromReport = true
        try forgive(loan, on: day(2026, 10, 5))
        try forgive(debt, on: day(2026, 10, 7))

        let spent = try store.graph(.spent)
        let income = try store.graph(.income)

        #expect(spent.popup(on: day(2026, 10, 4)).total == Money(cents: 0))
        #expect(spent.popup(on: day(2026, 10, 5)).total == Money(cents: 100_00))
        #expect(spent.headline == Money(cents: 100_00))
        #expect(income.popup(on: day(2026, 10, 6)).total == Money(cents: 0))
        #expect(income.popup(on: day(2026, 10, 7)).total == Money(cents: 250_00))
        #expect(income.headline == Money(cents: 250_00))
    }

    @Test func aBalanceAdjustmentCountsByItsCategory() throws {
        try Transaction.recordBalanceAdjustment(Money(cents: -12_00), in: checking, on: day(2026, 10, 4), in: context)
        try Transaction.recordBalanceAdjustment(
            Money(cents: 3_50), in: checking, on: day(2026, 10, 6),
            reason: store.category("Collect Interest", .income), in: context
        )

        #expect(try store.graph(.spent).headline == Money(cents: 12_00))
        #expect(try store.graph(.income).headline == Money(cents: 3_50))
    }

    @Test func nothingInRecentlyDeletedCounts() throws {
        let coffee = try store.record(-4_50, "Café", on: day(2026, 10, 3))
        let salary = try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        let loan = try record(.loan, 100_00, on: day(2026, 9, 20))
        try forgive(loan, on: day(2026, 10, 6))

        try [coffee, salary, loan].delete(.onlySelected, in: context)

        #expect(try store.graph(.spent).headline == Money(cents: 0))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    @Test func onlyTheWalletsCountedInTheTotalCount() throws {
        let brokerage = Wallet(name: "Brokerage")
        brokerage.includeInTotal = false
        let oldBank = Wallet(name: "Old bank")
        oldBank.isArchived = true
        let cash = Wallet(name: "Cash")
        for wallet in [brokerage, oldBank, cash] {
            context.insert(wallet)
        }
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(-500_00, "Investment", on: day(2026, 10, 3), in: brokerage)
        try store.record(900_00, "Salary", .income, on: day(2026, 10, 4), in: oldBank)
        try store.record(-25_00, "Café", on: day(2026, 10, 5), in: cash)
        try cash.delete()

        #expect(try store.graph(.spent).headline == Money(cents: 40_00))
        #expect(try store.graph(.income).headline == Money(cents: 0))
    }

    // MARK: The running total

    @Test func theLineStartsAtZeroAndAddsUpEachDayThroughToday() throws {
        try store.record(-7_00, "Café", on: day(2026, 9, 30))
        try store.record(-10_00, "Café", on: day(2026, 10, 1))
        try store.record(-20_00, "Products", on: day(2026, 10, 5))
        try store.record(-5_00, "Café", on: day(2026, 10, 5))
        try store.record(-3_00, "Café", on: today)
        try store.record(-100_00, "Rentals", on: day(2026, 10, 13))

        let spent = try store.graph(.spent)

        #expect(spent.line.map(\.total.cents) == [
            0, 10_00, 10_00, 10_00, 10_00, 35_00, 35_00, 35_00, 35_00, 35_00, 35_00, 35_00, 38_00,
        ])
        #expect(spent.headline == Money(cents: 38_00))
        #expect(spent.headline == spent.line.last?.total)
    }

    @Test func dayDOfAnNDayMonthSitsDOverNOfTheWayAcross() throws {
        let spent = try store.graph(.spent)

        #expect(spent.line.map(\.position) == (0...12).map { Double($0) / 31 })
        #expect(spent.position(of: today) == 12.0 / 31)
    }

    @Test func anEarlierMonthRunsThroughItsLastDay() throws {
        try store.record(-60_00, "Rentals", on: day(2026, 2, 1))
        try store.record(-15_00, "Café", on: day(2026, 2, 28))
        try store.record(-9_00, "Café", on: day(2026, 3, 1))

        let february = try store.graph(.spent, in: CalendarMonth(year: 2026, month: 2))

        #expect(february.line.count == 29)
        #expect(february.line.last?.position == 1)
        #expect(february.headline == Money(cents: 75_00))
        #expect(february.defaultSelection == day(2026, 2, 28))
    }

    @Test(arguments: SpentOrIncome.allCases)
    func withNothingToCountTheCardShowsAFlatLineAtZero(side: SpentOrIncome) throws {
        let card = try store.graph(side)

        #expect(card.line.count == 13)
        #expect(card.line.allSatisfy { $0.total == Money(cents: 0) })
        #expect(card.headline.formatted(locale: Locale(identifier: "en_US")) == "$0.00")
    }

    // MARK: The selected day

    @Test func todayIsSelectedAndItsPopupShowsTheDateAndTheAmountSoFar() throws {
        try store.record(-12_00, "Café", on: day(2026, 10, 2))
        try store.record(-3_00, "Café", on: today)

        let spent = try store.graph(.spent)
        let popup = spent.popup(on: spent.defaultSelection)

        #expect(spent.defaultSelection == today)
        #expect(popup.day == today)
        #expect(popup.total == Money(cents: 15_00))
        #expect(spent.position(of: spent.defaultSelection) == spent.line.last?.position)
    }

    @Test func aDayTheLineDoesNotReachYetHasNoAmountSoFar() throws {
        try store.record(-12_00, "Café", on: day(2026, 10, 2))

        let popup = try store.graph(.spent).popup(on: day(2026, 10, 20))

        #expect(popup.day == day(2026, 10, 20))
        #expect(popup.total == nil)
    }

    /// A day after today can be picked too, though the line doesn't reach it yet.
    @Test func aDragAcrossTheChartSnapsToTheDayWhoseEndIsNearest() throws {
        let spent = try store.graph(.spent)

        #expect(spent.day(nearest: 12.0 / 31) == today)
        #expect(spent.day(nearest: 12.4 / 31) == today)
        #expect(spent.day(nearest: 12.6 / 31) == day(2026, 10, 13))
        #expect(spent.day(nearest: 20.0 / 31) == day(2026, 10, 20))
    }

    @Test func aDragPastEitherEdgeStopsOnTheFirstOrLastDay() throws {
        let spent = try store.graph(.spent)

        #expect(spent.day(nearest: 0) == day(2026, 10, 1))
        #expect(spent.day(nearest: -0.2) == day(2026, 10, 1))
        #expect(spent.day(nearest: 1) == day(2026, 10, 31))
        #expect(spent.day(nearest: 1.3) == day(2026, 10, 31))
    }

    @Test func aSelectedDayShowsItsDateAndTheRunningTotalThroughIt() throws {
        try store.record(-12_00, "Café", on: day(2026, 10, 2))
        try store.record(-8_00, "Products", on: day(2026, 10, 5))

        let spent = try store.graph(.spent)
        let selected = spent.day(nearest: spent.position(of: day(2026, 10, 4)))
        let popup = spent.popup(on: selected)

        #expect(selected == day(2026, 10, 4))
        #expect(popup.day == day(2026, 10, 4))
        #expect(popup.total == Money(cents: 12_00))
    }
}
