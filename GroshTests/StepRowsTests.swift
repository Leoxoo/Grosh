import Testing
@testable import Grosh

/// The rows a Net income or Trend screen lists, one per Step: each Step's totals, which together make up the period's.
@MainActor
struct StepRowsTests {
    private let store: MonthGraphFixture
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// The Steps' Income and Spent add up to the period's, for a month split into weeks.
    @Test func theStepTotalsAddUpToThePeriodsTotals() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(-80_00, "Clothing", on: day(2026, 10, 9))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        try store.record(-25_00, "Café", on: day(2026, 10, 11))
        let october = DayRange(first: day(2026, 10, 1), last: day(2026, 10, 31))
        let counted = try store.transactions().counted(in: .total, during: .month(CalendarMonth(today)), today: today)

        let rows = StepRow.rows(of: counted, for: .month, over: october, today: today, firstWeekday: 2)

        // Today is the 12th, so the last week is cut to that day.
        #expect(rows.map(\.title) == ["1–4", "5–11", "10/12/2026"])
        #expect(rows.map { $0.totals.income.cents }.reduce(0, +) == 1_500_00)
        #expect(rows.map { $0.totals.spent.cents }.reduce(0, +) == 145_00)
        #expect(rows[1].totals == PeriodTotals(income: Money(cents: 1_500_00), spent: Money(cents: 105_00)))
    }

    /// A custom range split into quarters: each quarter's total is what counts in its days, and the quarters add up.
    @Test func quartersAddUpToTheCustomRange() throws {
        try store.record(-100_00, "Café", on: day(2025, 3, 20))
        try store.record(-200_00, "Café", on: day(2025, 8, 1))
        try store.record(-300_00, "Café", on: day(2026, 10, 2))
        let span = DayRange(first: day(2025, 3, 7), last: day(2026, 10, 16))
        let counted = try store.transactions().counted(in: .total, during: .custom(span), today: today)

        let rows = StepRow.rows(of: counted, for: .custom(span), over: span, today: today)

        #expect(rows.first?.title == "Q1/2025")
        #expect(rows.first?.totals.spent == Money(cents: 100_00))
        #expect(rows.map { $0.totals.spent.cents }.reduce(0, +) == 600_00)
        #expect(rows.map { $0.total(of: .spent).cents }.reduce(0, +) == 600_00)
    }
}
