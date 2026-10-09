import SwiftData
import Testing
@testable import Grosh

/// The Opening balance, Ending balance and difference at the top of the Transactions tab.
@MainActor
struct PeriodSummaryTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = Wallet(name: "Checking")
        container.mainContext.insert(checking)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func month(_ year: Int, _ month: Int) -> Period {
        .month(CalendarMonth(year: year, month: month))
    }

    @discardableResult
    private func record(_ cents: Int, on day: CalendarDay, excludedFromReport: Bool = false) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = checking
        transaction.isExcludedFromReport = excludedFromReport
        return transaction
    }

    private var transactions: [Transaction] { checking.transactions ?? [] }

    @Test func openingBalanceIsEverythingBeforeThePeriodAndEndingBalanceEverythingThroughItsLastDay() {
        record(100_00, on: day(2026, 7, 20))
        record(-30_00, on: day(2026, 8, 1))
        record(-12_50, on: day(2026, 8, 31))
        record(5_00, on: day(2026, 9, 1))

        let summary = PeriodSummary(of: transactions, in: month(2026, 8), today: today)

        #expect(summary.openingBalance == Money(cents: 100_00))
        #expect(summary.endingBalance == Money(cents: 57_50))
        #expect(summary.difference == Money(cents: -42_50))
    }

    @Test func eachPeriodOpensWithTheEndingBalanceOfThePeriodBeforeIt() {
        record(250_00, on: day(2026, 6, 30))
        record(-40_00, on: day(2026, 7, 1))
        record(-9_99, on: day(2026, 8, 31))
        record(1_200_00, on: day(2026, 9, 15))
        record(-75_00, on: today)
        record(-500_00, on: day(2026, 10, 10))
        record(-20_00, on: day(2027, 1, 1))
        let strip = TimeRange.month.periods(from: day(2026, 6, 30), today: today)

        let summaries = strip.map { PeriodSummary(of: transactions, in: $0, today: today) }

        #expect(summaries.map(\.openingBalance.cents) == [0, 250_00, 210_00, 200_01, 1_400_01, 1_325_01])
        #expect(summaries.map(\.endingBalance.cents) == [250_00, 210_00, 200_01, 1_400_01, 1_325_01, 805_01])
    }

    @Test func futureOpensWithTodaysBalanceAndEndsWithTheProjectedBalance() {
        record(100_00, on: day(2026, 10, 1))
        record(-30_00, on: day(2026, 10, 10))
        record(-20_00, on: day(2026, 12, 24))

        let summary = PeriodSummary(of: transactions, in: .future, today: today)

        #expect(summary.openingBalance == checking.balance(asOf: today))
        #expect(summary.endingBalance == Money(cents: 50_00))
        #expect(summary.difference == Money(cents: -50_00))
    }

    @Test func excludedTransactionsCountInBothBalances() {
        record(1_000_00, on: day(2026, 8, 3), excludedFromReport: true)
        record(-200_00, on: day(2026, 9, 3), excludedFromReport: true)

        let summary = PeriodSummary(of: transactions, in: month(2026, 9), today: today)

        #expect(summary.openingBalance == Money(cents: 1_000_00))
        #expect(summary.endingBalance == Money(cents: 800_00))
    }

    @Test func thisMonthEndsWithTheWalletsBalance() {
        record(100_00, on: day(2026, 9, 30))
        record(-12_00, on: today)
        record(-500_00, on: day(2026, 10, 31))

        let summary = PeriodSummary(of: transactions, in: month(2026, 10), today: today)

        #expect(summary.endingBalance == checking.balance(asOf: today))
        #expect(summary.endingBalance == Money(cents: 88_00))
    }
}
