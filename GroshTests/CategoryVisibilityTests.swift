import Testing
@testable import Grosh

@MainActor
struct CategoryVisibilityTests {
    private let store: CategoryFixture
    private var catalog: CategoryCatalog { store.catalog }

    init() throws {
        store = try CategoryFixture()
    }

    @Test func aHiddenCategoryStaysOnItsTransactionsButLeavesThePicker() throws {
        let cafe = try store.category("Café")
        let latte = store.spend(450, on: cafe)

        try catalog.setHidden(cafe, true)

        #expect(latte.category?.name == "Café")
        let picker = try catalog.pickerCategories(of: .expense).map(\.name)
        #expect(!picker.contains("Café"))
        #expect(picker.contains("Restaurants"))
    }

    @Test func hidingAParentTakesItsSubcategoriesOutOfThePickerToo() throws {
        try catalog.setHidden(try store.category("Food & Beverage"), true)

        let picker = try catalog.pickerCategories(of: .expense).map(\.name)
        #expect(!picker.contains("Food & Beverage"))
        #expect(!picker.contains("Café"))
        #expect(!picker.contains("Restaurants"))
        #expect(picker.first == "Products")
    }

    @Test func thePickerNeverOffersCategoriesOnlyTheAppFilesUnder() throws {
        let expense = try catalog.pickerCategories(of: .expense).map(\.name)
        let income = try catalog.pickerCategories(of: .income).map(\.name)

        #expect(!expense.contains("Outgoing transfer"))
        #expect(expense.last == "Other Expense")
        #expect(!income.contains("Incoming transfer"))
        #expect(income.last == "Other Income")
        #expect(try catalog.pickerCategories(of: .debtLoan).map(\.name) == ["Loan", "Debt"])
        #expect(try catalog.pickerCategories(of: .system).isEmpty)
    }

    @Test func hiddenCategoriesShowInTheListOnlyWhenAskedFor() throws {
        try catalog.setHidden(try store.category("Food & Beverage"), true)
        try catalog.setHidden(try store.category("Pets"), true)

        let shown = try catalog.categories(of: .expense, includingHidden: false).map(\.name)
        let all = try catalog.categories(of: .expense, includingHidden: true).map(\.name)

        #expect(shown.count == 60)
        #expect(!shown.contains("Café"))
        #expect(!shown.contains("Pets"))
        #expect(all.count == 64)
        #expect(Array(all.prefix(3)) == ["Food & Beverage", "Café", "Restaurants"])
    }

    @Test func unhidingPutsACategoryBackInThePicker() throws {
        let pets = try store.category("Pets")
        try catalog.setHidden(pets, true)

        try catalog.setHidden(pets, false)

        #expect(try catalog.pickerCategories(of: .expense).map(\.name).contains("Pets"))
    }

    @Test func lockedCategoriesCantBeHidden() throws {
        let otherExpense = try store.category("Other Expense")

        #expect(throws: CategoryError.locked) {
            try catalog.setHidden(otherExpense, true)
        }
        #expect(!otherExpense.isHidden)
    }
}
