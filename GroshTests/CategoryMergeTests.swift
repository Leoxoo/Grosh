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

    @Test func mergingASubcategoryMovesItsTransactionsToTheTargetAndRemovesIt() throws {
        let cafe = try store.category("Café")
        let restaurants = try store.category("Restaurants")
        let latte = store.spend(450, on: cafe)
        let espresso = store.spend(300, on: cafe)
        let dinner = store.spend(4_200, on: restaurants)

        try catalog.merge(cafe, into: restaurants)

        #expect(latte.category?.name == "Restaurants")
        #expect(espresso.category?.name == "Restaurants")
        #expect(dinner.category?.name == "Restaurants")
        #expect(try !store.categoryExists("Café"))
        #expect(try store.category("Food & Beverage").children?.map(\.name) == ["Restaurants"])
    }

    @Test func mergingAParentMovesItsSubcategoriesUnderTheTarget() throws {
        let otherTransport = try store.category("Other Transport")
        let personalTransport = try store.category("Personal Transport")
        let busPass = store.spend(9_000, on: otherTransport)
        let ride = store.spend(2_350, on: try store.category("Taxi"))

        try catalog.merge(otherTransport, into: personalTransport)

        #expect(busPass.category?.name == "Personal Transport")
        #expect(ride.category?.name == "Taxi")
        #expect(try store.category("Taxi").parent?.name == "Personal Transport")
        #expect(Set((personalTransport.children ?? []).map(\.name)) == [
            "Vehicle Maintenance", "Parking Fees", "Petrol", "Taxi", "Public Transport", "Other Fuel",
        ])
        #expect(try !store.categoryExists("Other Transport"))
    }

    @Test func mergingATopLevelCategoryWithoutSubcategoriesMovesItsTransactions() throws {
        let withdrawal = try store.category("Withdrawal")
        let atm = store.spend(10_000, on: withdrawal)

        try catalog.merge(withdrawal, into: try store.category("Unknown transaction"))

        #expect(atm.category?.name == "Unknown transaction")
        #expect(try !store.categoryExists("Withdrawal"))
    }

    @Test(arguments: [
        ("Other Expense", "Products"),
        ("Products", "Other Expense"),
        ("Outgoing transfer", "Other Expense"),
    ])
    func lockedCategoriesCantBeMergedEitherWay(source: String, target: String) throws {
        let lockedOrNot = try store.category(source)
        let purchase = store.spend(1_000, on: lockedOrNot)

        #expect(throws: CategoryRuleError.locked) {
            try catalog.merge(lockedOrNot, into: try store.category(target))
        }
        #expect(purchase.category?.name == source)
        #expect(try store.categoryExists(source))
    }

    @Test func aCategoryCantBeMergedIntoAnotherType() throws {
        #expect(throws: CategoryRuleError.differentType) {
            try catalog.merge(try store.category("Gifts & Donations"), into: try store.category("Gifts", .income))
        }
        #expect(try store.categoryExists("Gifts & Donations"))
    }

    @Test func aCategoryCantBeMergedIntoItself() throws {
        let products = try store.category("Products")
        #expect(throws: CategoryRuleError.sameCategory) {
            try catalog.merge(products, into: products)
        }
        #expect(try store.categoryExists("Products"))
    }

    @Test(arguments: [
        ("Other Transport", "Petrol"),
        ("Personal Transport", "Petrol"),
    ])
    func aParentWithSubcategoriesCantBeMergedIntoASubcategory(source: String, target: String) throws {
        #expect(throws: CategoryRuleError.tooDeep) {
            try catalog.merge(try store.category(source), into: try store.category(target))
        }
        #expect(try store.category("Taxi").parent?.name == "Other Transport")
        #expect(try store.category("Petrol").parent?.name == "Personal Transport")
    }

    @Test func aSubcategoryCanBeMergedIntoItsOwnParent() throws {
        let petrol = try store.category("Petrol")
        let fillUp = store.spend(5_500, on: petrol)

        try catalog.merge(petrol, into: try store.category("Personal Transport"))

        #expect(fillUp.category?.name == "Personal Transport")
        #expect(try !store.categoryExists("Petrol"))
    }

    @Test func aSubcategoryCanBeMergedIntoAnyUnlockedCategoryOfItsType() throws {
        let targets = try catalog.mergeTargets(for: try store.category("Petrol")).map(\.name)

        #expect(targets.contains("Personal Transport"))
        #expect(targets.contains("Taxi"))
        #expect(targets.contains("Products"))
        #expect(!targets.contains("Petrol"))
        #expect(!targets.contains("Other Expense"))
        #expect(!targets.contains("Salary"))
        #expect(targets.count == 61)
    }

    @Test func aParentWithSubcategoriesCanOnlyBeMergedIntoAnotherTopLevelCategory() throws {
        let targets = try catalog.mergeTargets(for: try store.category("Other Transport")).map(\.name)

        #expect(targets.first == "Food & Beverage")
        #expect(targets.contains("Personal Transport"))
        #expect(!targets.contains("Taxi"))
        #expect(!targets.contains("Petrol"))
        #expect(!targets.contains("Other Transport"))
        #expect(targets.count == 19)
    }

    @Test func lockedCategoriesHaveNoMergeTargets() throws {
        #expect(try catalog.mergeTargets(for: try store.category("Other Expense")).isEmpty)
    }
}
