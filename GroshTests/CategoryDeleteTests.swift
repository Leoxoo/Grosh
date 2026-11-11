import SwiftData
import Testing
@testable import Grosh

@MainActor
@Suite(.namedInTheLog)
struct CategoryDeleteTests {
    private let store: TestStore
    private var catalog: CategoryCatalog { store.catalog }

    init() throws {
        store = try TestStore()
    }

    /// Whether Delete is offered for `category`, counted as Account → Categories counts it.
    private func canDelete(_ category: Grosh.Category) -> Bool {
        CategoryCatalog.canDelete(category, inUse: catalog.inUse([category]))
    }

    @Test func aCategoryWithoutTransactionsCanBeDeleted() throws {
        let pets = try store.category("Pets")
        #expect(canDelete(pets))

        try catalog.delete(pets)

        #expect(try !store.categoryExists("Pets"))
    }

    @Test func aCategoryWithTransactionsCantBeDeleted() throws {
        let pets = try store.category("Pets")
        let vet = store.spend(12_000, on: pets)
        #expect(!canDelete(pets))

        #expect(throws: CategoryRuleError.hasTransactions) {
            try catalog.delete(pets)
        }
        #expect(vet.category?.name == "Pets")
    }

    @Test func deletingAParentDeletesItsSubcategoriesToo() throws {
        try catalog.delete(try store.category("Guns and Ammo"))

        #expect(try !store.categoryExists("Guns and Ammo"))
        #expect(try !store.categoryExists("Ammo"))
        #expect(try !store.categoryExists("Range"))
    }

    @Test func aParentCantBeDeletedWhileASubcategoryHasTransactions() throws {
        let gunsAndAmmo = try store.category("Guns and Ammo")
        store.spend(2_500, on: try store.category("Range"))
        #expect(!canDelete(gunsAndAmmo))

        #expect(throws: CategoryRuleError.hasTransactions) {
            try catalog.delete(gunsAndAmmo)
        }
        #expect(try store.category("Range").parent?.name == "Guns and Ammo")
    }

    @Test func theListCountsEveryRowsTransactionsAtOnce() throws {
        let pets = try store.category("Pets")
        let gunsAndAmmo = try store.category("Guns and Ammo")
        let range = try store.category("Range")
        store.spend(2_500, on: range)

        let inUse = catalog.inUse([pets, gunsAndAmmo, range])

        #expect(inUse == [gunsAndAmmo.persistentModelID, range.persistentModelID])
        #expect(CategoryCatalog.canDelete(pets, inUse: inUse))
        #expect(!CategoryCatalog.canDelete(gunsAndAmmo, inUse: inUse))
    }

    @Test(arguments: ["Other Expense", "Outgoing transfer"])
    func lockedCategoriesCantBeDeleted(name: String) throws {
        let locked = try store.category(name)
        #expect(!canDelete(locked))

        #expect(throws: CategoryRuleError.locked) {
            try catalog.delete(locked)
        }
        #expect(try store.categoryExists(name))
    }
}
