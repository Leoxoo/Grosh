import SwiftData
import Testing
@testable import Grosh

/// Tapping a Card shows its transactions one period at a time with their total: by statement period for a Credit card
/// with a statement date, by calendar month for any other Card.
@MainActor
struct CardTransactionsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    private func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }

    private func addCard(_ name: String, kind: CardKind = .credit, statementDay: Int? = nil) throws -> Card {
        try Card.create(CardDraft(name: name, kind: kind, payingWallet: checking, statementDay: statementDay), in: context)
    }

    /// Records a transaction of `cents` (negative for money going out) paid with `card`.
    @discardableResult
    private func record(_ cents: Int, on day: CalendarDay, paidWith card: Card?) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = checking
        transaction.category = try context.otherCategory(cents > 0 ? .income : .expense)
        transaction.card = card
        return transaction
    }

    // MARK: Which periods

    @Test func aCreditCardWithAStatementDateOpensOnItsCurrentStatementPeriod() throws {
        let chase = try addCard("Chase", statementDay: 15)

        let current = chase.period(containing: today)

        #expect(current.isStatement)
        #expect(current.days == DayRange(first: day(9, 16), last: day(10, 15)))
    }

    @Test func aStatementDateOfThe31stOpensOnPeriodsEndingOnTheMonthsLastDay() throws {
        let appleCard = try addCard("Apple Card", statementDay: 31)

        #expect(appleCard.period(containing: day(2, 14)).days == DayRange(first: day(2, 1), last: day(2, 28)))
        #expect(appleCard.period(containing: day(2, 14, 2028)).days == DayRange(first: day(2, 1, 2028), last: day(2, 29, 2028)))
    }

    @Test func aDebitCardAndACreditCardWithoutAStatementDateShowCalendarMonths() throws {
        let debit = try addCard("Navy Federal Debit", kind: .debit)
        let petal = try addCard("Petal")
        let october = DayRange(first: day(10, 1), last: day(10, 31))

        #expect(!debit.period(containing: today).isStatement)
        #expect(debit.period(containing: today).days == october)
        #expect(!petal.period(containing: today).isStatement)
        #expect(petal.period(containing: today).days == october)
    }

    // MARK: A period's transactions and total

    @Test func aStatementPeriodListsOnlyThisCardsTransactionsBetweenItsStatementDates() throws {
        let chase = try addCard("Chase", statementDay: 15)
        let amex = try addCard("Amex", statementDay: 15)
        try record(-20_00, on: day(9, 15), paidWith: chase)
        let first = try record(-12_76, on: day(9, 16), paidWith: chase)
        let refund = try record(5_00, on: day(10, 1), paidWith: chase)
        let excluded = try record(-100_00, on: day(10, 2), paidWith: chase)
        excluded.isExcludedFromReport = true
        // Dated after today, but before the statement closes, so it is on this statement.
        let last = try record(-30_00, on: day(10, 15), paidWith: chase)
        try record(-7_00, on: day(10, 16), paidWith: chase)
        try record(-50_00, on: day(10, 1), paidWith: amex)
        try record(-9_00, on: day(10, 1), paidWith: nil)

        let shown = chase.transactions(in: chase.period(containing: today))

        #expect(Set(shown) == [first, refund, excluded, last])
        #expect(shown.net == Money(cents: -137_76))
    }

    @Test func steppingBackShowsThePreviousStatementsTransactions() throws {
        let chase = try addCard("Chase", statementDay: 15)
        let september = try record(-20_00, on: day(9, 15), paidWith: chase)
        let august = try record(-40_00, on: day(8, 16), paidWith: chase)
        try record(-12_76, on: day(9, 16), paidWith: chase)

        let previous = chase.transactions(in: chase.period(containing: today).adding(-1))

        #expect(Set(previous) == [september, august])
        #expect(previous.net == Money(cents: -60_00))
    }

    @Test func aCalendarMonthListsTheCardsTransactionsOfTheWholeMonth() throws {
        let debit = try addCard("Navy Federal Debit", kind: .debit)
        try record(-20_00, on: day(9, 30), paidWith: debit)
        let first = try record(-12_76, on: day(10, 1), paidWith: debit)
        let last = try record(-30_00, on: day(10, 31), paidWith: debit)

        let shown = debit.transactions(in: debit.period(containing: today))

        #expect(Set(shown) == [first, last])
        #expect(shown.net == Money(cents: -42_76))
    }

    // MARK: How far ‹ › step

    @Test func withoutTransactionsThereIsOnlyTheCurrentPeriod() throws {
        let chase = try addCard("Chase", statementDay: 15)
        let current = chase.period(containing: today)

        #expect(chase.periods(today: today) == current...current)
    }

    @Test func stepsReachBackToTheFirstTransactionsPeriodAndForwardToTheCurrentOne() throws {
        let chase = try addCard("Chase", statementDay: 15)
        try record(-20_00, on: day(6, 16), paidWith: chase)
        try record(-12_76, on: day(9, 1), paidWith: chase)

        let periods = chase.periods(today: today)

        #expect(periods.lowerBound.days == DayRange(first: day(6, 16), last: day(7, 15)))
        #expect(periods.upperBound == chase.period(containing: today))
    }

    @Test func stepsReachForwardToAPeriodHoldingATransactionDatedAfterToday() throws {
        let chase = try addCard("Chase", statementDay: 15)
        try record(-20_00, on: day(12, 1), paidWith: chase)

        let periods = chase.periods(today: today)

        #expect(periods.lowerBound == chase.period(containing: today))
        #expect(periods.upperBound.days == DayRange(first: day(11, 16), last: day(12, 15)))
    }
}
