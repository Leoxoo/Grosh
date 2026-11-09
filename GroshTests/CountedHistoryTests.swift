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

    private func history(_ selection: WalletSelection = .total) throws -> CountedHistory {
        try CountedHistory(store.transactions(), in: selection, otherIncome: store.otherIncome())
    }

    /// A wallet named `name` whose Starting balance is dated `day`.
    @discardableResult
    private func wallet(_ name: String, startingOn day: CalendarDay) throws -> Wallet {
        var draft = WalletDraft()
        draft.name = name
        return try Wallet.create(draft, startingBalance: Money(cents: 300_00), on: day, in: context)
    }

    /// Savings' Starting balance in May counts toward neither side, so its strip starts in August, with its first
    /// Income, and never holds Future.
    @Test func theStripStartsWithTheFirstMonthAnythingCountsForTheSelection() throws {
        let savings = try wallet("Savings", startingOn: day(2026, 5, 1))
        try store.record(-15_00, "Café", on: day(2026, 3, 4))
        try store.record(50_00, "Salary", .income, on: day(2026, 8, 31), in: savings)

        #expect(try history(.wallet(savings)).strip(.month, today: today) == [
            .month(CalendarMonth(year: 2026, month: 8)), .month(CalendarMonth(year: 2026, month: 9)),
            .month(CalendarMonth(year: 2026, month: 10)),
        ])
        #expect(try history().firstDay == day(2026, 3, 4))
    }

    /// All time runs from the first day anything counts through today.
    @Test func allTimeRunsFromTheFirstDayAnythingCounts() throws {
        try wallet("Cash", startingOn: day(2026, 5, 1))
        try store.record(-15_00, "Café", on: day(2026, 6, 4))

        #expect(try history().days(of: .all, today: today) == DayRange(first: day(2026, 6, 4), last: today))
    }

    /// All time and a custom range have no fixed length, so they have no comparison graph; a week does.
    @Test func onlyAFixedLengthPeriodHasAGraph() throws {
        try store.record(-15_00, "Café", on: day(2026, 10, 4))
        let total = try history()

        #expect(total.graph(.spent, in: .all, recurring: [], today: today, comparingWith: .average) == nil)
        #expect(total.graph(.spent, in: .day(today), recurring: [], today: today, comparingWith: .average) == nil)
        let week = total.graph(
            .spent, in: .week(startingOn: day(2026, 10, 4)), recurring: [], today: today, comparingWith: .average
        )
        #expect(week?.headline == Money(cents: 15_00))
    }
}
