import SwiftData
import Testing
@testable import Grosh

/// What counts for a wallet selection, worked out once for a Report screen: the strip, the days of All time, and the
/// comparison card's graph all start from the first day anything counts.
@MainActor
@Suite(.namedInTheLog)
struct CountedHistoryTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A wallet named `name` whose Starting balance is dated `day`.
    @discardableResult
    private func wallet(_ name: String, startingOn day: CalendarDay) throws -> Wallet {
        var draft = WalletDraft(currencyCode: Money.defaultCurrencyCode)
        draft.name = name
        return try Wallet.create(draft, startingBalance: Money(cents: 300_00), on: day, in: context)
    }

    /// Savings' Starting balance in May counts toward neither side, so its strip starts in August, with its first
    /// Income, and never holds Future.
    @Test func theStripStartsWithTheFirstMonthAnythingCountsForTheSelection() throws {
        let savings = try wallet("Savings", startingOn: day(2026, 5, 1))
        try store.record(-15_00, "Café", on: day(2026, 3, 4))
        try store.record(50_00, "Salary", .income, on: day(2026, 8, 31), in: savings)

        #expect(try store.history(.wallet(savings)).strip(.month, today: today) == [
            .month(CalendarMonth(year: 2026, month: 8)), .month(CalendarMonth(year: 2026, month: 9)),
            .month(CalendarMonth(year: 2026, month: 10)),
        ])
        #expect(try store.history().firstDay == day(2026, 3, 4))
    }

    /// All time runs from the first day anything counts through today.
    @Test func allTimeRunsFromTheFirstDayAnythingCounts() throws {
        try wallet("Cash", startingOn: day(2026, 5, 1))
        try store.record(-15_00, "Café", on: day(2026, 6, 4))

        #expect(try store.history().days(of: .all, today: today) == DayRange(first: day(2026, 6, 4), last: today))
    }

    /// All time and a custom range have no fixed length, so they have no comparison graph; a week does.
    @Test func onlyAFixedLengthPeriodHasAGraph() throws {
        try store.record(-15_00, "Café", on: day(2026, 10, 4))
        let total = try store.history()

        #expect(total.graph(.spent, in: .all, recurring: .none, today: today, comparingWith: .average) == nil)
        #expect(total.graph(.spent, in: .day(today), recurring: .none, today: today, comparingWith: .average) == nil)
        let week = total.graph(
            .spent, in: .week(startingOn: day(2026, 10, 4)), recurring: .none, today: today, comparingWith: .average
        )
        #expect(week?.headline == Money(cents: 15_00))
    }

    /// A figure is in one currency: the Total of a USD and a EUR wallet counts the USD wallet's transactions under the
    /// USD label, and leaves the EUR wallet's out instead of adding euros to dollars.
    @Test func theTotalCountsOnlyTheTransactionsInItsCurrency() throws {
        let euros = try Wallet.create(
            name: "Euros", startingBalance: Money(cents: 300_00, currencyCode: "EUR"), on: day(2026, 5, 1), in: context
        )
        try store.record(-15_00, "Café", on: day(2026, 10, 4))
        try store.record(-40_00, "Café", on: day(2026, 10, 5), in: euros)
        let wallets = try context.fetch(Wallet.unarchived)
        let total = try CountedHistory(
            store.transactions(), in: .total, currencyCode: WalletSelection.total.currencyCode(among: wallets),
            otherIncome: store.otherIncome()
        )

        #expect(total.currencyCode == "USD")
        #expect(total.counted.map(\.amount) == [Money(cents: 15_00)])
        let inEuros = try CountedHistory(
            store.transactions(), in: .wallet(euros), currencyCode: "EUR", otherIncome: store.otherIncome()
        )
        #expect(inEuros.counted.map(\.amount) == [Money(cents: 40_00, currencyCode: "EUR")])
    }
}
