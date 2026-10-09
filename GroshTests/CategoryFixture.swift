import SwiftData
import Testing
@testable import Grosh

/// An in-memory store seeded with the default category tree and one wallet, for category tests.
@MainActor
struct CategoryFixture {
    let container: ModelContainer
    let wallet: Wallet
    var context: ModelContext { container.mainContext }
    var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        wallet = Wallet(name: "Checking")
        container.mainContext.insert(wallet)
    }

    func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == name && $0.type == type })
    }

    func categoryExists(_ name: String) throws -> Bool {
        try context.fetch(FetchDescriptor<Grosh.Category>()).contains { $0.name == name }
    }

    /// Records an expense of `cents` under `category`.
    @discardableResult
    func spend(_ cents: Int, on category: Grosh.Category) -> Transaction {
        let transaction = Transaction(
            amount: Money(cents: -cents), day: CalendarDay(year: 2026, month: 10, day: 1),
            wallet: wallet, category: category
        )
        context.insert(transaction)
        return transaction
    }
}
