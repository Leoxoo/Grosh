import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The order a category list shows its choices in, the most used lately first, and the search that narrows it.
@MainActor
@Suite(.namedInTheLog)
struct CategoryChoiceOrderTests {
    private let fixture: CategoryFixture
    private let today = CalendarDay(year: 2026, month: 10, day: 16)

    init() throws {
        fixture = try CategoryFixture()
    }

    private var expenseTree: [Grosh.Category] {
        get throws { try fixture.catalog.pickerCategories(of: .expense) }
    }

    /// Records `count` expenses under `name`, dated `day` or today.
    @discardableResult
    private func spend(
        _ count: Int, on name: String, day: CalendarDay? = nil
    ) throws -> [Transaction] {
        let category = try fixture.category(name)
        return (0..<count).map { _ in
            let transaction = Transaction(
                amount: Money(cents: -10_00), day: day ?? today, wallet: fixture.wallet, category: category
            )
            fixture.context.insert(transaction)
            return transaction
        }
    }

    private func arranged() throws -> [String] {
        let tree = try expenseTree
        let transactions = try fixture.context.fetch(FetchDescriptor<Transaction>())
        return CategoryCatalog.byRecentUse(tree, transactions: transactions, today: today).map(\.name)
    }

    @Test func unusedCategoriesKeepTheirTreeOrder() throws {
        #expect(try arranged() == expenseTree.map(\.name))
    }

    @Test func theCategoryUsedMostComesFirst() throws {
        try spend(3, on: "Products")
        try spend(1, on: "Café")

        let names = try arranged()

        #expect(Array(names.prefix(3)) == ["Products", "Food & Beverage", "Café"])
    }

    @Test func aMuchUsedSubcategoryLiftsItsParentButKeepsItsPlaceWithinIt() throws {
        try spend(2, on: "Internet Bill")

        let names = try arranged()
        let bills = try fixture.category("Bills & Utilities")
        let billsInTreeOrder = try expenseTree.filter { $0 == bills || $0.parent == bills }.map(\.name)

        #expect(Array(names.prefix(billsInTreeOrder.count)) == billsInTreeOrder)
        #expect(names[1] == "Phone Bill")
    }

    @Test func onlyTheLastThirtyDaysCount() throws {
        try spend(3, on: "Products", day: today.adding(days: -30))
        try spend(1, on: "Shopping", day: today.adding(days: -29))

        let names = try arranged()

        // Products' transactions are 31 days old, so it stays behind Food & Beverage, as in tree order.
        #expect(names.first == "Shopping")
        #expect(names.firstIndex(of: "Food & Beverage")! < names.firstIndex(of: "Products")!)
    }

    @Test func deletedAndFutureTransactionsDontCount() throws {
        try spend(2, on: "Products", day: today.adding(days: 1))
        for transaction in try spend(2, on: "Products") {
            transaction.deletedAt = .now
        }
        try spend(1, on: "Shopping")

        let names = try arranged()

        #expect(names.first == "Shopping")
        #expect(names.firstIndex(of: "Food & Beverage")! < names.firstIndex(of: "Products")!)
    }

    @Test func searchMatchesNamesWhateverTheCaseAndAccents() throws {
        let tree = try expenseTree

        #expect(CategoryCatalog.matching("cafe", in: tree).map(\.name) == ["Café"])
        let bills = CategoryCatalog.matching("BILL", in: tree).map(\.name)
        #expect(bills.contains("Bills & Utilities"))
        #expect(bills.contains("Phone Bill"))
        #expect(bills.allSatisfy { $0.localizedCaseInsensitiveContains("bill") })
    }

    @Test func anEmptySearchKeepsEveryCategory() throws {
        let tree = try expenseTree

        #expect(CategoryCatalog.matching("  ", in: tree).map(\.name) == tree.map(\.name))
    }
}
