import SwiftData
import Testing
@testable import Grosh

@MainActor
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
        #expect(categories.count == 83)
        #expect(categories.filter { $0.type == .expense }.count == 64)
        #expect(categories.filter { $0.type == .income }.count == 14)
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
            "Starting balance", "Loan", "Debt", "Debt Collection", "Repayment",
        ])
    }

    @Test func seedingAgainDoesNotDuplicateTheTree() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        try CategorySeeder.seedIfNeeded(in: context)

        #expect(try allCategories().count == 83)
    }
}
