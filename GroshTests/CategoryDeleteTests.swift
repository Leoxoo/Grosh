import Testing
@testable import Grosh

@MainActor
struct CategoryDeleteTests {
    private let store: CategoryFixture
    private var catalog: CategoryCatalog { store.catalog }

    init() throws {
        store = try CategoryFixture()
    }

    @Test func aCategoryWithoutTransactionsCanBeDeleted() throws {
        let pets = try store.category("Pets")
        #expect(catalog.canDelete(pets))

        try catalog.delete(pets)

        #expect(try !store.categoryExists("Pets"))
    }

    @Test func aCategoryWithTransactionsCantBeDeleted() throws {
        let pets = try store.category("Pets")
        let vet = store.spend(12_000, on: pets)
        #expect(!catalog.canDelete(pets))

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
        #expect(!catalog.canDelete(gunsAndAmmo))

        #expect(throws: CategoryRuleError.hasTransactions) {
            try catalog.delete(gunsAndAmmo)
        }
        #expect(try store.category("Range").parent?.name == "Guns and Ammo")
    }

    @Test(arguments: ["Other Expense", "Outgoing transfer"])
    func lockedCategoriesCantBeDeleted(name: String) throws {
        let locked = try store.category(name)
        #expect(!catalog.canDelete(locked))

        #expect(throws: CategoryRuleError.locked) {
            try catalog.delete(locked)
        }
        #expect(try store.categoryExists(name))
    }
}
