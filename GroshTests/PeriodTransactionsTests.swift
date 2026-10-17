import Testing
@testable import Grosh

/// The transactions a Net income or Trend row lists for its Step: what counts in its days, toward one side or both.
@MainActor
struct PeriodTransactionsTests {
    private let store: MonthGraphFixture

    init() throws {
        store = try MonthGraphFixture()
    }

    private var october: DayRange { DayRange(first: day(2026, 10, 1), last: day(2026, 10, 12)) }

    @Test func aSideListsOnlyItsOwnTransactionsInTheDays() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        try store.record(-20_00, "Café", on: day(2026, 10, 20))

        let spent = PeriodTransactions(side: .spent, of: try store.transactions(), in: .total, days: october)
        #expect(spent.transactions.count == 1)
        #expect(spent.total == Money(cents: 40_00))
    }

    /// With no side, every transaction in the days is listed and the total is Net income.
    @Test func withoutASideTheTotalIsNetIncome() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))

        let both = PeriodTransactions(side: nil, of: try store.transactions(), in: .total, days: october)
        #expect(both.transactions.count == 2)
        #expect(both.total == Money(cents: 1_460_00))
    }

    @Test func listsNewestDayFirst() throws {
        try store.record(-10_00, "Café", on: day(2026, 10, 2))
        try store.record(-30_00, "Café", on: day(2026, 10, 9))

        let listed = PeriodTransactions(side: .spent, of: try store.transactions(), in: .total, days: october)
        #expect(listed.transactions.map(\.day) == [day(2026, 10, 9), day(2026, 10, 2)])
    }
}
