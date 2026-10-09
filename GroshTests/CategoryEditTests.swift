import Testing
@testable import Grosh

@MainActor
struct CategoryEditTests {
    private let store: CategoryFixture
    private var catalog: CategoryCatalog { store.catalog }

    init() throws {
        store = try CategoryFixture()
    }

    private func names(_ type: CategoryType) throws -> [String] {
        try catalog.categories(of: type).map(\.name)
    }

    @Test func addingACategoryPutsItAtTheEndOfItsType() throws {
        let added = try catalog.add(CategoryDraft(name: "Hobbies", type: .expense, symbolName: "paintpalette.fill", color: .purple))

        #expect(try names(.expense).last == "Hobbies")
        #expect(added.symbolName == "paintpalette.fill")
        #expect(added.color == .purple)
        #expect(added.parent == nil)
        #expect(try !names(.income).contains("Hobbies"))
    }

    @Test(arguments: ["Products", "café", " RESTAURANTS "])
    func namesAreUniqueWithinAType(name: String) throws {
        #expect(throws: CategoryRuleError.nameTaken) {
            try catalog.add(CategoryDraft(name: name, type: .expense))
        }
        #expect(try names(.expense).count == 64)
    }

    @Test func theSameNameMayBeUsedByAnotherType() throws {
        try catalog.add(CategoryDraft(name: "Salary", type: .expense))

        #expect(try names(.expense).contains("Salary"))
        #expect(try names(.income).contains("Salary"))
    }

    @Test(arguments: ["", "   "])
    func aCategoryNeedsAName(name: String) throws {
        #expect(throws: CategoryRuleError.nameRequired) {
            try catalog.add(CategoryDraft(name: name, type: .expense))
        }
    }

    @Test func namesAreSavedWithoutSurroundingSpaces() throws {
        let added = try catalog.add(CategoryDraft(name: "  Hobbies ", type: .expense))

        #expect(added.name == "Hobbies")
    }

    @Test func aSubcategoryIsAddedAfterItsParentsOtherSubcategories() throws {
        let food = try store.category("Food & Beverage")

        try catalog.add(CategoryDraft(name: "Bakery", type: .expense, parent: food))

        #expect(Array(try names(.expense).prefix(4)) == ["Food & Beverage", "Café", "Restaurants", "Bakery"])
    }

    @Test func aSubcategoryCantHaveSubcategories() throws {
        #expect(throws: CategoryRuleError.tooDeep) {
            try catalog.add(CategoryDraft(name: "Espresso", type: .expense, parent: try store.category("Café")))
        }
    }

    @Test func aSubcategoryHasItsParentsType() throws {
        #expect(throws: CategoryRuleError.differentType) {
            try catalog.add(CategoryDraft(name: "Bonus", type: .income, parent: try store.category("Products")))
        }
    }

    @Test func lockedCategoriesCantHaveSubcategories() throws {
        #expect(throws: CategoryRuleError.locked) {
            try catalog.add(CategoryDraft(name: "Misc", type: .expense, parent: try store.category("Other Expense")))
        }
    }

    @Test func editingChangesTheNameAndIcon() throws {
        let cafe = try store.category("Café")
        var draft = CategoryDraft(cafe)
        draft.name = "Coffee"
        draft.symbolName = "mug.fill"
        draft.color = .orange

        try catalog.update(cafe, to: draft)

        #expect(cafe.name == "Coffee")
        #expect(cafe.symbolName == "mug.fill")
        #expect(cafe.color == .orange)
        #expect(cafe.parent?.name == "Food & Beverage")
    }

    @Test func aCategoryMayKeepItsOwnNameInAnotherCase() throws {
        let cafe = try store.category("Café")
        var draft = CategoryDraft(cafe)
        draft.name = "CAFÉ"

        try catalog.update(cafe, to: draft)

        #expect(cafe.name == "CAFÉ")
    }

    @Test func renamingToAnotherCategorysNameIsRefused() throws {
        let cafe = try store.category("Café")
        var draft = CategoryDraft(cafe)
        draft.name = "Restaurants"

        #expect(throws: CategoryRuleError.nameTaken) {
            try catalog.update(cafe, to: draft)
        }
        #expect(cafe.name == "Café")
    }

    @Test func aSubcategoryCanMoveToAnotherParentOrToTheTopLevel() throws {
        let taxi = try store.category("Taxi")
        let parking = try store.category("Parking Fees")
        var toPersonal = CategoryDraft(taxi)
        toPersonal.parent = try store.category("Personal Transport")
        var toTop = CategoryDraft(parking)
        toTop.parent = nil

        try catalog.update(taxi, to: toPersonal)
        try catalog.update(parking, to: toTop)

        #expect(try store.category("Personal Transport").children?.count == 3)
        #expect(taxi.parent?.name == "Personal Transport")
        #expect(parking.parent == nil)
        #expect(try names(.expense).last == "Parking Fees")
    }

    @Test func aParentWithSubcategoriesCantMoveUnderAnotherCategory() throws {
        let food = try store.category("Food & Beverage")
        var draft = CategoryDraft(food)
        draft.parent = try store.category("Shopping")

        #expect(throws: CategoryRuleError.tooDeep) {
            try catalog.update(food, to: draft)
        }
        #expect(food.parent == nil)
    }

    @Test func aCategoryWithoutTransactionsCanChangeTypeTakingItsSubcategoriesAlong() throws {
        let school = try store.category("School extra", .income)
        var draft = CategoryDraft(school)
        draft.type = .expense

        try catalog.update(school, to: draft)

        #expect(school.type == .expense)
        #expect(try store.category("VA").parent?.name == "School extra")
        #expect(try names(.expense).suffix(2) == ["School extra", "VA"])
        #expect(try !names(.income).contains("VA"))
    }

    @Test func aSubcategoryThatChangesTypeNeedsAParentOfTheNewType() throws {
        let va = try store.category("VA", .income)
        var keepsParent = CategoryDraft(va)
        keepsParent.type = .expense
        var toTop = keepsParent
        toTop.parent = nil

        #expect(throws: CategoryRuleError.differentType) {
            try catalog.update(va, to: keepsParent)
        }
        try catalog.update(va, to: toTop)

        #expect(va.type == .expense)
        #expect(va.parent == nil)
    }

    @Test(arguments: ["Gifts & Donations", "Charity"])
    func aCategoryWithTransactionsKeepsItsType(spentOn name: String) throws {
        let parent = try store.category("Gifts & Donations")
        store.spend(5_000, on: try store.category(name))
        var draft = CategoryDraft(parent)
        draft.type = .income

        #expect(throws: CategoryRuleError.hasTransactions) {
            try catalog.update(parent, to: draft)
        }
        #expect(parent.type == .expense)
    }

    @Test func aCategoryCantChangeTypeIfASubcategoryNameIsTakenThere() throws {
        try catalog.add(CategoryDraft(name: "Charity", type: .income))
        let gifts = try store.category("Gifts & Donations")
        var draft = CategoryDraft(gifts)
        draft.type = .income

        #expect(throws: CategoryRuleError.nameTaken) {
            try catalog.update(gifts, to: draft)
        }
        #expect(gifts.type == .expense)
    }

    @Test(arguments: [
        ("Other Expense", CategoryType.expense),
        ("Loan", .debtLoan),
        ("Starting balance", .system),
    ])
    func aLockedCategorysIconCanChange(name: String, type: CategoryType) throws {
        let locked = try store.category(name, type)
        var draft = CategoryDraft(locked)
        draft.symbolName = "star.fill"
        draft.color = .pink

        try catalog.update(locked, to: draft)

        #expect(locked.symbolName == "star.fill")
        #expect(locked.color == .pink)
    }

    @Test func aLockedCategoryCantBeRenamedRetypedOrMoved() throws {
        let otherExpense = try store.category("Other Expense")
        var renamed = CategoryDraft(otherExpense)
        renamed.name = "Misc"
        var retyped = CategoryDraft(otherExpense)
        retyped.type = .income
        var moved = CategoryDraft(otherExpense)
        moved.parent = try store.category("Products")

        for draft in [renamed, retyped, moved] {
            #expect(throws: CategoryRuleError.locked) {
                try catalog.update(otherExpense, to: draft)
            }
        }
        #expect(otherExpense.name == "Other Expense")
        #expect(otherExpense.type == .expense)
        #expect(otherExpense.parent == nil)
    }

    @Test func theParentsOfferedAreTheUnlockedTopLevelCategoriesOfTheType() throws {
        let options = try catalog.parentOptions(of: .income, for: nil).map(\.name)

        #expect(options == [
            "Salary", "Tips", "Extra work", "Award", "Selling", "Sombodypaid", "School extra",
            "Cashback", "Tax Return", "Collect Interest", "Gifts",
        ])
    }

    @Test func aCategoryIsNotOfferedAsItsOwnParent() throws {
        let options = try catalog.parentOptions(of: .income, for: try store.category("Tips", .income)).map(\.name)

        #expect(!options.contains("Tips"))
        #expect(options.count == 10)
    }

    @Test func aParentWithSubcategoriesIsOfferedNoParent() throws {
        #expect(try catalog.parentOptions(of: .income, for: try store.category("School extra", .income)).isEmpty)
    }

    @Test(arguments: [CategoryType.debtLoan, .system])
    func onlyExpenseAndIncomeCategoriesCanBeAdded(type: CategoryType) throws {
        #expect(throws: CategoryRuleError.fixedType) {
            try catalog.add(CategoryDraft(name: "Mortgage", type: type))
        }
    }
}
