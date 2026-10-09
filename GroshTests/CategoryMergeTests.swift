import SwiftData
import Testing
@testable import Grosh

@MainActor
struct CategoryMergeTests {
    private let store: CategoryFixture
    private var catalog: CategoryCatalog { store.catalog }

    init() throws {
        store = try CategoryFixture()
    }

    private func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try store.category(name, type)
    }

    private func categoryExists(_ name: String) throws -> Bool {
        try store.categoryExists(name)
    }

    @discardableResult
    private func spend(_ cents: Int, on category: Grosh.Category) -> Transaction {
        store.spend(cents, on: category)
    }

    @Test func mergingASubcategoryMovesItsTransactionsToTheTargetAndRemovesIt() throws {
        let cafe = try category("Café")
        let restaurants = try category("Restaurants")
        let latte = spend(450, on: cafe)
        let espresso = spend(300, on: cafe)
        let dinner = spend(4_200, on: restaurants)

        try catalog.merge(cafe, into: restaurants)

        #expect(latte.category?.name == "Restaurants")
        #expect(espresso.category?.name == "Restaurants")
        #expect(dinner.category?.name == "Restaurants")
        #expect(try !categoryExists("Café"))
        #expect(try category("Food & Beverage").children?.map(\.name) == ["Restaurants"])
    }

    @Test func mergingAParentMovesItsSubcategoriesUnderTheTarget() throws {
        let otherTransport = try category("Other Transport")
        let personalTransport = try category("Personal Transport")
        let busPass = spend(9_000, on: otherTransport)
        let ride = spend(2_350, on: try category("Taxi"))

        try catalog.merge(otherTransport, into: personalTransport)

        #expect(busPass.category?.name == "Personal Transport")
        #expect(ride.category?.name == "Taxi")
        #expect(try category("Taxi").parent?.name == "Personal Transport")
        #expect(Set((personalTransport.children ?? []).map(\.name)) == [
            "Vehicle Maintenance", "Parking Fees", "Petrol", "Taxi", "Public Transport", "Other Fuel",
        ])
        #expect(try !categoryExists("Other Transport"))
    }

    @Test func mergingATopLevelCategoryWithoutSubcategoriesMovesItsTransactions() throws {
        let withdrawal = try category("Withdrawal")
        let atm = spend(10_000, on: withdrawal)

        try catalog.merge(withdrawal, into: try category("Unknown transaction"))

        #expect(atm.category?.name == "Unknown transaction")
        #expect(try !categoryExists("Withdrawal"))
    }

    @Test(arguments: [
        ("Other Expense", "Products"),
        ("Products", "Other Expense"),
        ("Outgoing transfer", "Other Expense"),
    ])
    func lockedCategoriesCantBeMergedEitherWay(source: String, target: String) throws {
        let lockedOrNot = try category(source)
        let purchase = spend(1_000, on: lockedOrNot)

        #expect(throws: CategoryError.locked) {
            try catalog.merge(lockedOrNot, into: try category(target))
        }
        #expect(purchase.category?.name == source)
        #expect(try categoryExists(source))
    }

    @Test func aCategoryCantBeMergedIntoAnotherType() throws {
        #expect(throws: CategoryError.differentType) {
            try catalog.merge(try category("Gifts & Donations"), into: try category("Gifts", .income))
        }
        #expect(try categoryExists("Gifts & Donations"))
    }

    @Test func aCategoryCantBeMergedIntoItself() throws {
        let products = try category("Products")
        #expect(throws: CategoryError.sameCategory) {
            try catalog.merge(products, into: products)
        }
        #expect(try categoryExists("Products"))
    }

    @Test(arguments: [
        ("Other Transport", "Petrol"),
        ("Personal Transport", "Petrol"),
    ])
    func aParentWithSubcategoriesCantBeMergedIntoASubcategory(source: String, target: String) throws {
        #expect(throws: CategoryError.tooDeep) {
            try catalog.merge(try category(source), into: try category(target))
        }
        #expect(try category("Taxi").parent?.name == "Other Transport")
        #expect(try category("Petrol").parent?.name == "Personal Transport")
    }

    @Test func aSubcategoryCanBeMergedIntoItsOwnParent() throws {
        let petrol = try category("Petrol")
        let fillUp = spend(5_500, on: petrol)

        try catalog.merge(petrol, into: try category("Personal Transport"))

        #expect(fillUp.category?.name == "Personal Transport")
        #expect(try !categoryExists("Petrol"))
    }

    @Test func aSubcategoryCanBeMergedIntoAnyUnlockedCategoryOfItsType() throws {
        let targets = try catalog.mergeTargets(for: try category("Petrol")).map(\.name)

        #expect(targets.contains("Personal Transport"))
        #expect(targets.contains("Taxi"))
        #expect(targets.contains("Products"))
        #expect(!targets.contains("Petrol"))
        #expect(!targets.contains("Other Expense"))
        #expect(!targets.contains("Salary"))
        #expect(targets.count == 61)
    }

    @Test func aParentWithSubcategoriesCanOnlyBeMergedIntoAnotherTopLevelCategory() throws {
        let targets = try catalog.mergeTargets(for: try category("Other Transport")).map(\.name)

        #expect(targets.first == "Food & Beverage")
        #expect(targets.contains("Personal Transport"))
        #expect(!targets.contains("Taxi"))
        #expect(!targets.contains("Petrol"))
        #expect(!targets.contains("Other Transport"))
        #expect(targets.count == 19)
    }

    @Test func lockedCategoriesHaveNoMergeTargets() throws {
        #expect(try catalog.mergeTargets(for: try category("Other Expense")).isEmpty)
    }
}
