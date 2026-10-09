import Foundation
import SwiftData
import Testing
@testable import Grosh

@MainActor
struct CategorySeedTests {
    // The context doesn't keep its container alive, so the test holds on to it.
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    func allCategories() throws -> [Grosh.Category] {
        try context.fetch(FetchDescriptor<Grosh.Category>())
    }

    @Test func firstLaunchSeedsTheFullTree() throws {
        try CategorySeed.seedIfNeeded(context)

        #expect(try allCategories().count == 83)
    }

    @Test func categoriesAreSeededUnderTheirTypes() throws {
        try CategorySeed.seedIfNeeded(context)

        let countByType = Dictionary(grouping: try allCategories(), by: \.type).mapValues(\.count)
        #expect(countByType == [.expense: 64, .income: 14, .debtLoan: 4, .system: 1])
    }

    @Test func lockedCategoriesAreTheOnesTheAppDependsOn() throws {
        try CategorySeed.seedIfNeeded(context)

        let locked = try allCategories().filter(\.isLocked)
        #expect(Set(locked.map(\.name)) == [
            "Outgoing transfer", "Incoming transfer", "Other Income", "Other Expense", "Starting balance",
            "Loan", "Debt", "Debt Collection", "Repayment",
        ])
        #expect(Set(locked.compactMap(\.role)) == Set(CategoryRole.allCases))
    }

    @Test func subcategoriesNestOneLevelUnderTheirParent() throws {
        try CategorySeed.seedIfNeeded(context)
        let all = try allCategories()
        let food = try #require(all.first { $0.name == "Food & Beverage" })
        let schoolExtra = try #require(all.first { $0.name == "School extra" })

        #expect(food.parent == nil)
        #expect(food.children?.sorted { $0.sortOrder < $1.sortOrder }.map(\.name) == ["Café", "Restaurants"])
        #expect(schoolExtra.children?.map(\.name) == ["VA"])
        #expect(schoolExtra.children?.map(\.type) == [.income])
        #expect(all.allSatisfy { $0.parent?.parent == nil })
    }

    @Test func secondLaunchDoesNotDuplicateTheTree() throws {
        try CategorySeed.seedIfNeeded(context)
        try CategorySeed.seedIfNeeded(context)

        #expect(try allCategories().count == 83)
    }
}
