import SwiftData
import Testing
@testable import Grosh

/// Tapping a Card shows its transactions one period at a time with their total: by statement period for a Credit card
/// with a statement date, by calendar month for any other Card.
@MainActor
@Suite(.namedInTheLog)
struct CardTransactionsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    /// Records a transaction of `cents` (negative for money going out) paid with `card`.
    @discardableResult
    private func record(_ cents: Int, on day: CalendarDay, paidWith card: Card?) throws -> Transaction {
        context.record(
            cents, on: day, in: checking, under: try context.otherCategory(cents > 0 ? .income : .expense), card: card
        )
    }

    // MARK: Which periods

    @Test func aCreditCardWithAStatementDateOpensOnItsCurrentStatementPeriod() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)

        let current = chase.period(containing: today)

        #expect(current.isStatement)
        #expect(current.days == DayRange(first: day(2026, 9, 16), last: day(2026, 10, 15)))
    }

    /// Creating or editing a Card refuses a statement date on a Debit card, but a Card stored as Debit with one still
    /// shows calendar months.
    @Test func aDebitCardShowsCalendarMonthsEvenWithAStatementDate() throws {
        let card = try context.addCard("Navy Federal", paidFrom: checking, statementDay: 15)
        card.kind = .debit

        let current = card.period(containing: today)

        #expect(!current.isStatement)
        #expect(current.days == DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31)))
    }

    // MARK: A period's transactions and total

    @Test func aStatementPeriodListsOnlyThisCardsTransactionsBetweenItsStatementDates() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let amex = try context.addCard("Amex", paidFrom: checking, statementDay: 15)
        try record(-20_00, on: day(2026, 9, 15), paidWith: chase)
        let first = try record(-12_76, on: day(2026, 9, 16), paidWith: chase)
        let refund = try record(5_00, on: day(2026, 10, 1), paidWith: chase)
        let excluded = try record(-100_00, on: day(2026, 10, 2), paidWith: chase)
        excluded.isExcludedFromReport = true
        // Dated after today, but before the statement closes, so it is on this statement.
        let last = try record(-30_00, on: day(2026, 10, 15), paidWith: chase)
        try record(-7_00, on: day(2026, 10, 16), paidWith: chase)
        try record(-50_00, on: day(2026, 10, 1), paidWith: amex)
        try record(-9_00, on: day(2026, 10, 1), paidWith: nil)

        let shown = chase.transactions(in: chase.period(containing: today))

        #expect(Set(shown) == [first, refund, excluded, last])
        #expect(shown.charged == Money(cents: -137_76))
    }

    @Test func steppingBackShowsThePreviousStatementsTransactions() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let september = try record(-20_00, on: day(2026, 9, 15), paidWith: chase)
        let august = try record(-40_00, on: day(2026, 8, 16), paidWith: chase)
        try record(-12_76, on: day(2026, 9, 16), paidWith: chase)

        let previous = chase.transactions(in: chase.period(containing: today).adding(-1))

        #expect(Set(previous) == [september, august])
        #expect(previous.charged == Money(cents: -60_00))
    }

    @Test func aCalendarMonthListsTheCardsTransactionsOfTheWholeMonth() throws {
        let debit = try context.addCard("Navy Federal Debit", kind: .debit, paidFrom: checking)
        try record(-20_00, on: day(2026, 9, 30), paidWith: debit)
        let first = try record(-12_76, on: day(2026, 10, 1), paidWith: debit)
        let last = try record(-30_00, on: day(2026, 10, 31), paidWith: debit)

        let shown = debit.transactions(in: debit.period(containing: today))

        #expect(Set(shown) == [first, last])
        #expect(shown.charged == Money(cents: -42_76))
    }

    // MARK: Lead-in transactions

    @Test func aStatementPeriodLeadsInWithTheTwoDaysBeforeItBegins() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)

        #expect(chase.period(containing: today).leadInDays == DayRange(first: day(2026, 9, 14), last: day(2026, 9, 15)))
    }

    @Test func aCalendarMonthHasNoLeadIn() throws {
        let debit = try context.addCard("Navy Federal Debit", kind: .debit, paidFrom: checking)
        let petal = try context.addCard("Petal", paidFrom: checking)
        try record(-20_00, on: day(2026, 9, 30), paidWith: debit)
        try record(-20_00, on: day(2026, 9, 30), paidWith: petal)

        #expect(debit.period(containing: today).leadInDays == nil)
        #expect(debit.leadInTransactions(in: debit.period(containing: today)).isEmpty)
        #expect(petal.leadInTransactions(in: petal.period(containing: today)).isEmpty)
    }

    @Test func leadInTransactionsAreThisCardsFromTheTwoDaysBeforeAndStayOnThePreviousStatement() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let amex = try context.addCard("Amex", paidFrom: checking, statementDay: 15)
        try record(-1_00, on: day(2026, 9, 13), paidWith: chase)
        let fourteenth = try record(-20_00, on: day(2026, 9, 14), paidWith: chase)
        let fifteenth = try record(-30_00, on: day(2026, 9, 15), paidWith: chase)
        let first = try record(-12_76, on: day(2026, 9, 16), paidWith: chase)
        try record(-50_00, on: day(2026, 9, 15), paidWith: amex)
        let current = chase.period(containing: today)

        #expect(Set(chase.leadInTransactions(in: current)) == [fourteenth, fifteenth])
        #expect(Set(chase.transactions(in: current.adding(-1))).isSuperset(of: [fourteenth, fifteenth]))
        #expect(chase.transactions(in: current) == [first])
    }

    @Test func leadInTransactionsNeverCountInTheStatementTotalUnlessAdded() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let leadIn = try record(-20_00, on: day(2026, 9, 15), paidWith: chase)
        try record(-30_00, on: day(2026, 9, 14), paidWith: chase)
        try record(-12_76, on: day(2026, 9, 16), paidWith: chase)
        let current = chase.period(containing: today)
        let shown = chase.transactions(in: current)

        #expect(shown.charged == Money(cents: -12_76))
        let added = chase.leadInTransactions(in: current).filter { $0 == leadIn }
        #expect((shown + added).charged == Money(cents: -32_76))
    }

    // MARK: How far ‹ › step

    @Test func withoutTransactionsThereIsOnlyTheCurrentPeriod() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let current = chase.period(containing: today)

        #expect(chase.periods(today: today) == current...current)
    }

    @Test func stepsReachBackToTheFirstTransactionsPeriodAndForwardToTheCurrentOne() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        try record(-20_00, on: day(2026, 6, 16), paidWith: chase)
        try record(-12_76, on: day(2026, 9, 1), paidWith: chase)

        let periods = chase.periods(today: today)

        #expect(periods.lowerBound.days == DayRange(first: day(2026, 6, 16), last: day(2026, 7, 15)))
        #expect(periods.upperBound == chase.period(containing: today))
    }

    @Test func stepsReachForwardToAPeriodHoldingATransactionDatedAfterToday() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        try record(-20_00, on: day(2026, 12, 1), paidWith: chase)

        let periods = chase.periods(today: today)

        #expect(periods.lowerBound == chase.period(containing: today))
        #expect(periods.upperBound.days == DayRange(first: day(2026, 11, 16), last: day(2026, 12, 15)))
    }
}
