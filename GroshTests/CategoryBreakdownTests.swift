import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Category report's split of a side's period total by parent category: what each donut slice and each Breakdown row
/// holds. Subcategories add into their parent, and the five largest parents get a slice each, the rest sharing one.
@MainActor
struct CategoryBreakdownTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// The breakdown of `side` for October, the Total, from every transaction in the store.
    private func breakdown(_ side: SpentOrIncome) throws -> CategoryBreakdown {
        let counted = try store.transactions().counted(
            in: .total, during: .month(CalendarMonth(today)), today: today
        )
        return CategoryBreakdown(side: side, of: counted)
    }

    /// Each slice as its name and amount in cents, the Everything else slice by its name in the Report.
    private func describe(_ slices: [CategoryBreakdown.Slice]) -> [(String, Int)] {
        slices.map { slice in
            switch slice {
            case .category(let total): (total.category.name, total.total.cents)
            case .everythingElse(let total): ("Everything else", total.cents)
            }
        }
    }

    // MARK: Parent categories

    @Test func subcategoriesAddIntoTheirParentAndADirectTransactionCountsThere() throws {
        try store.record(-30_00, "Phone Bill", on: day(2026, 10, 2))
        try store.record(-20_00, "Electricity Bill", on: day(2026, 10, 4))
        try store.record(-10_00, "Bills & Utilities", on: day(2026, 10, 6))

        let spent = try breakdown(.spent)
        #expect(spent.categories.map(\.category.name) == ["Bills & Utilities"])
        #expect(spent.categories.map(\.total.cents) == [60_00])
        #expect(describe(spent.slices).map(\.0) == ["Bills & Utilities"])
        #expect(spent.total == Money(cents: 60_00))
    }

    @Test func theCategoriesAreListedLargestFirst() throws {
        try store.record(-20_00, "Café", on: day(2026, 10, 2))
        try store.record(-50_00, "Clothing", on: day(2026, 10, 3))

        #expect(try breakdown(.spent).categories.map(\.category.name) == ["Shopping", "Food & Beverage"])
    }

    /// Income and Spent are split separately: money in never shows in the Spent breakdown.
    @Test func eachSideHoldsOnlyItsOwnCategories() throws {
        try store.record(-40_00, "Café", on: day(2026, 10, 3))
        try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))

        #expect(try breakdown(.spent).categories.map(\.category.name) == ["Food & Beverage"])
        #expect(try breakdown(.income).categories.map(\.category.name) == ["Salary"])
        #expect(try breakdown(.income).total == Money(cents: 1_500_00))
    }

    // MARK: Donut slices

    @Test func theFiveLargestParentsEachGetASliceAndTheRestShareEverythingElse() throws {
        try store.record(-700_00, "Food & Beverage", on: day(2026, 10, 1))
        try store.record(-600_00, "Products", on: day(2026, 10, 1))
        try store.record(-500_00, "Bills & Utilities", on: day(2026, 10, 1))
        try store.record(-400_00, "Personal Transport", on: day(2026, 10, 1))
        try store.record(-300_00, "Other Transport", on: day(2026, 10, 1))
        try store.record(-200_00, "Clothing", on: day(2026, 10, 1))
        try store.record(-100_00, "Health & Fitness", on: day(2026, 10, 1))

        let spent = try breakdown(.spent)
        #expect(describe(spent.slices).map(\.0) == [
            "Food & Beverage", "Products", "Bills & Utilities", "Personal Transport", "Other Transport", "Everything else",
        ])
        #expect(describe(spent.slices).map(\.1) == [700_00, 600_00, 500_00, 400_00, 300_00, 300_00])
    }

    @Test func fiveOrFewerParentsGetNoEverythingElse() throws {
        try store.record(-400_00, "Food & Beverage", on: day(2026, 10, 1))
        try store.record(-300_00, "Products", on: day(2026, 10, 1))
        try store.record(-200_00, "Bills & Utilities", on: day(2026, 10, 1))
        try store.record(-100_00, "Personal Transport", on: day(2026, 10, 1))
        try store.record(-50_00, "Other Transport", on: day(2026, 10, 1))

        #expect(describe(try breakdown(.spent).slices).map(\.1) == [400_00, 300_00, 200_00, 100_00, 50_00])
    }

    /// A parent whose refunds outweigh what was spent has no slice, though it still has its row in the Breakdown.
    @Test func aCategoryWhoseTotalIsNotAboveZeroGetsNoSlice() throws {
        try store.record(-80_00, "Clothing", on: day(2026, 10, 2))
        try store.record(100_00, "Clothing", on: day(2026, 10, 4))
        try store.record(-40_00, "Café", on: day(2026, 10, 3))

        let spent = try breakdown(.spent)
        #expect(spent.categories.map(\.category.name) == ["Food & Beverage", "Shopping"])
        #expect(spent.categories.map(\.total.cents) == [40_00, -20_00])
        #expect(describe(spent.slices).map(\.0) == ["Food & Beverage"])
    }

    /// The category a forgiven Loan is filed under gets its amount, as the Month graph counts it.
    @Test func aForgivenLoanCountsUnderTheCategoryItsAmountIsFiledUnder() throws {
        let loan = try store.lendOrBorrow(.loan, 250_00, on: day(2026, 9, 20))
        try store.forgive(loan, on: day(2026, 10, 5))

        let spent = try breakdown(.spent)
        #expect(spent.categories.map(\.category.name) == ["Other Expense"])
        #expect(spent.categories.map(\.total.cents) == [250_00])
    }

    // MARK: Shares

    /// Percents are of what the categories above zero add up to, so the Breakdown's percents total 100%.
    @Test func sharesAreOfWhatTheCategoriesAboveZeroAddUpTo() throws {
        try store.record(-700_00, "Food & Beverage", on: day(2026, 10, 1))
        try store.record(-300_00, "Products", on: day(2026, 10, 1))
        try store.record(-80_00, "Clothing", on: day(2026, 10, 2))
        try store.record(100_00, "Clothing", on: day(2026, 10, 4))

        let spent = try breakdown(.spent)
        #expect(spent.share(of: Money(cents: 700_00)) == 0.7)
        #expect(spent.share(of: Money(cents: 300_00)) == 0.3)
        #expect(spent.share(of: Money(cents: -20_00)) == 0)
    }
}
