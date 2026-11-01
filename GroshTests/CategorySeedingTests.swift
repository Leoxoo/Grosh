import SwiftData
import Testing
@testable import Grosh

@MainActor
@Suite(.namedInTheLog)
struct CategorySeedingTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func allCategories() throws -> [Grosh.Category] {
        try context.fetch(FetchDescriptor<Grosh.Category>())
    }

    private func category(named name: String) throws -> Grosh.Category? {
        try allCategories().first { $0.name == name }
    }

    @Test func firstLaunchSeedsTheWholeTreeFromTheSpec() throws {
        try CategorySeeder.seedIfNeeded(in: context)

        let categories = try allCategories()
        #expect(categories.count == 84)
        #expect(categories.filter { $0.type == .expense }.count == 64)
        #expect(categories.filter { $0.type == .income }.count == 15)
        #expect(categories.filter { $0.type == .debtLoan }.count == 4)
    }

    @Test func subcategoriesHangUnderTheirParent() throws {
        try CategorySeeder.seedIfNeeded(in: context)

        let bills = try #require(try category(named: "Bills & Utilities"))
        #expect(bills.parent == nil)
        #expect(Set((bills.children ?? []).map(\.name)) == [
            "Phone Bill", "Water Bill", "Electricity Bill", "Gas Bill",
            "Valet/Trash Bill", "Internet Bill", "Rentals",
        ])
        #expect(try category(named: "VA")?.parent?.name == "School extra")
        #expect(try category(named: "Apps")?.parent?.name == "Entertainment")
        #expect(try category(named: "Products")?.parent == nil)
    }

    @Test func theAppsOwnCategoriesAreLocked() throws {
        try CategorySeeder.seedIfNeeded(in: context)

        let locked = try allCategories().filter(\.isLocked).map(\.name)
        #expect(Set(locked) == [
            "Outgoing transfer", "Incoming transfer", "Other Income", "Other Expense",
            "Starting balance", "Loan", "Debt", "Debt Collection", "Repayment", "Reimbursement",
        ])
    }

    @Test func aSeededStoreHasEveryCategoryTheAppDependsOn() throws {
        let seeded = try GroshStore.makeSeededContainer(inMemory: true)

        for role in LockedRole.allCases {
            #expect(try seeded.mainContext.lockedCategory(role).lockedRole == role)
        }
    }

    @Test func seedingAgainDoesNotDuplicateTheTree() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        try CategorySeeder.seedIfNeeded(in: context)

        #expect(try allCategories().count == 84)
    }

    /// A store upgraded from an older build keeps its categories, but their icons and locked roles came back empty.
    @Test func anUpgradedStoreGetsItsIconsAndLockedCategoriesBack() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        for category in try allCategories() {
            category.symbolName = "questionmark"
            category.lockedRole = nil
        }
        try context.save()

        try CategorySeeder.restoreMissingDefaults(in: context)

        #expect(try allCategories().count == 84)
        #expect(try category(named: "Food & Beverage")?.symbolName == "fork.knife")
        #expect(try allCategories().allSatisfy { $0.symbolName != "questionmark" })
        for role in LockedRole.allCases {
            #expect(try context.lockedCategory(role).lockedRole == role)
        }
    }

    /// An icon the user chose is kept; only the placeholder is replaced.
    @Test func restoringKeepsAnIconTheUserChose() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let products = try #require(try category(named: "Products"))
        products.symbolName = "star.fill"
        try context.save()

        try CategorySeeder.restoreMissingDefaults(in: context)

        #expect(products.symbolName == "star.fill")
    }

    /// A locked category that has gone missing comes back under its seeded name and type.
    @Test func aMissingLockedCategoryIsAddedBack() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        context.delete(try #require(try category(named: "Other Income")))
        try context.save()

        try CategorySeeder.restoreMissingDefaults(in: context)

        let restored = try context.lockedCategory(.otherIncome)
        #expect(restored.name == "Other Income")
        #expect(restored.type == .income)
        #expect(try allCategories().count == 84)
    }

    /// Running the repair on a complete store changes nothing.
    @Test func restoringACompleteStoreChangesNothing() throws {
        try CategorySeeder.seedIfNeeded(in: context)

        try CategorySeeder.restoreMissingDefaults(in: context)

        #expect(try allCategories().count == 84)
        #expect(try allCategories().filter(\.isLocked).count == 10)
        #expect(try category(named: "Food & Beverage")?.symbolName == "fork.knife")
    }

    /// An upgraded store can have every category as an Expense; the repair brings the seeded types back.
    @Test func anUpgradedStoreGetsItsCategoryTypesBack() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        for category in try allCategories() {
            category.type = .expense
            category.symbolName = "questionmark"
            category.lockedRole = nil
        }
        try context.save()

        try CategorySeeder.restoreMissingDefaults(in: context)

        #expect(try allCategories().filter { $0.type == .expense }.count == 64)
        #expect(try allCategories().filter { $0.type == .income }.count == 15)
        #expect(try allCategories().filter { $0.type == .debtLoan }.count == 4)
        #expect(try context.lockedCategory(.otherIncome).type == .income)
    }

    /// A store that still has Income categories is left alone, so a type the user changed is kept.
    @Test func aStoreWithIncomeCategoriesKeepsItsTypes() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let salary = try #require(try category(named: "Salary"))
        salary.type = .expense
        try context.save()

        try CategorySeeder.restoreMissingDefaults(in: context)

        #expect(salary.type == .expense)
    }

}
