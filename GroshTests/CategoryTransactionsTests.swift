import Testing
@testable import Grosh

/// The transactions a Breakdown row opens: what counts toward a side under a parent category, subcategories included, in
/// the days of the period. Their total is the row's amount.
@MainActor
struct CategoryTransactionsTests {
    private let store: MonthGraphFixture
    private var today: CalendarDay { store.today }
    private var october: DayRange { DayRange(first: day(2026, 10, 1), last: day(2026, 10, 12)) }

    init() throws {
        store = try MonthGraphFixture()
    }

    private func listed(_ parent: String, _ side: SpentOrIncome = .spent) throws -> CategoryTransactions {
        try CategoryTransactions(
            parent: store.category(parent), side: side, of: store.transactions(), in: .total, days: october,
            otherIncome: store.otherIncome()
        )
    }

    /// The subcategory's, the parent's own and another subcategory's transactions are all listed under the parent, newest
    /// day first, and their total is what the Breakdown shows for the parent.
    @Test func listsSubcategoriesAndTheParentNewestFirstAndTotalsThemLikeTheBreakdown() throws {
        try store.record(-30_00, "Phone Bill", on: day(2026, 10, 2))
        try store.record(-20_00, "Electricity Bill", on: day(2026, 10, 9))
        try store.record(-10_00, "Bills & Utilities", on: day(2026, 10, 5))
        try store.record(-99_00, "Café", on: day(2026, 10, 5))

        let rows = try listed("Bills & Utilities")
        #expect(rows.transactions.map(\.day) == [day(2026, 10, 9), day(2026, 10, 5), day(2026, 10, 2)])
        #expect(rows.total == Money(cents: 60_00))

        let breakdown = CategoryBreakdown(
            side: .spent,
            of: try store.transactions().counted(
                in: .total, during: .custom(october), today: today, otherIncome: store.otherIncome()
            )
        )
        let row = try #require(breakdown.categories.first { $0.category.name == "Bills & Utilities" })
        #expect(rows.total == row.total)
    }

    @Test func leavesOutOtherSidesDaysAndCategories() throws {
        try store.record(-30_00, "Phone Bill", on: day(2026, 10, 2))
        try store.record(-40_00, "Phone Bill", on: day(2026, 9, 30))
        try store.record(-50_00, "Phone Bill", on: day(2026, 10, 13))
        try store.record(1_000_00, "Salary", .income, on: day(2026, 10, 3))

        let rows = try listed("Bills & Utilities")
        #expect(rows.transactions.count == 1)
        #expect(rows.total == Money(cents: 30_00))
    }
}
