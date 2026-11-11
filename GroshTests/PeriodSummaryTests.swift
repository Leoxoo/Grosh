import SwiftData
import Testing
@testable import Grosh

/// The Opening balance, Ending balance and difference at the top of the Transactions tab, for a month. How the periods
/// of every time range chain together, and the period holding today and Future, are in `TimeRangeBalanceTests`.
@MainActor
@Suite(.namedInTheLog)
struct PeriodSummaryTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = container.mainContext.addWallet("Checking")
    }

    private func month(_ year: Int, _ month: Int) -> Period {
        .month(CalendarMonth(year: year, month: month))
    }

    @discardableResult
    private func record(_ cents: Int, on day: CalendarDay, excludedFromReport: Bool = false) -> Transaction {
        let transaction = context.record(cents, on: day, in: checking)
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

    @Test func excludedTransactionsCountInBothBalances() {
        record(1_000_00, on: day(2026, 8, 3), excludedFromReport: true)
        record(-200_00, on: day(2026, 9, 3), excludedFromReport: true)

        let summary = PeriodSummary(of: transactions, in: month(2026, 9), today: today)

        #expect(summary.openingBalance == Money(cents: 1_000_00))
        #expect(summary.endingBalance == Money(cents: 800_00))
    }
}
