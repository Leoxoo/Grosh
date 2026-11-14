import Foundation
import SwiftData
import Testing
@testable import Grosh

/// What Reward category each of the user's Expense categories counts as (its Rewards as), and the user's own Reward
/// categories. A subcategory follows its parent until it sets its own; anything nobody mapped is Everything else.
@MainActor
@Suite(.namedInTheLog)
struct RewardCategoryTests {
    private let store: TestStore
    private var rewards: RewardCategories { RewardCategories(context: store.context) }

    init() throws {
        store = try TestStore()
    }

    /// Saves `category` with `rewardsAs` as its own Rewards as, through the Category editor's draft.
    private func set(_ category: Grosh.Category, to rewardsAs: String?) throws {
        var draft = CategoryDraft(category)
        draft.ownRewardsAs = rewardsAs
        try store.catalog.update(category, to: draft)
    }

    @Test func anExpenseCategoryCanCountAsAnyRewardCategory() throws {
        let products = try store.category("Products")
        for reward in RewardCategory.fixed {
            try set(products, to: reward.id)
            #expect(products.rewardsAs == reward.id)
        }
    }

    @Test func aCategoryNobodyMappedCountsAsEverythingElse() throws {
        #expect(try store.category("Education").rewardsAs == RewardCategory.everythingElse.id)
        #expect(try store.category("Doctor").rewardsAs == RewardCategory.everythingElse.id)
        #expect(try store.category("Other Expense").rewardsAs == RewardCategory.everythingElse.id)
    }

    @Test func incomeDebtLoanAndTheAppsOwnCategoriesHaveNoRewardsAs() throws {
        let salary = try store.category("Salary", .income)
        try set(salary, to: "dining")
        #expect(salary.rewardsAs == nil)
        #expect(!salary.offersRewardsAs)
        #expect(try store.category("Loan", .debtLoan).rewardsAs == nil)
        #expect(try store.category("Starting balance", .system).rewardsAs == nil)
        #expect(try store.category("Outgoing transfer").rewardsAs == nil)
        #expect(try !store.category("Other Expense").offersRewardsAs)
    }

    @Test func aLockedCategoryKeepsNoRewardsAsOfItsOwn() throws {
        let other = try store.category("Other Expense")
        var draft = CategoryDraft(other)
        draft.ownRewardsAs = "dining"
        try store.catalog.update(other, to: draft)
        #expect(other.rewardsAs == RewardCategory.everythingElse.id)
    }

    @Test func aSubcategoryFollowsItsParentUntilItSetsItsOwn() throws {
        let parent = try store.category("Shopping")
        let child = try store.category("Books")
        try set(parent, to: "department-stores")
        #expect(child.rewardsAs == "department-stores")
        try set(parent, to: "online-shopping")
        #expect(child.rewardsAs == "online-shopping")
    }

    @Test func aSubcategoryKeepsItsOwnWhenItsParentChanges() throws {
        let parent = try store.category("Shopping")
        let child = try store.category("Books")
        try set(child, to: RewardCategory.everythingElse.id)
        try set(parent, to: "department-stores")
        #expect(child.rewardsAs == RewardCategory.everythingElse.id)
        try set(child, to: nil)
        #expect(child.rewardsAs == "department-stores")
    }

    @Test func aNewCategoryTakesTheRewardsAsItWasAddedWith() throws {
        var draft = CategoryDraft(name: "Bakery", type: .expense)
        draft.ownRewardsAs = "dining"
        #expect(try store.catalog.add(draft).rewardsAs == "dining")
    }

    @Test func aCategoryRetypedToIncomeDropsItsRewardsAsAndItsSubcategoriesToo() throws {
        let parent = try store.category("Guns and Ammo")
        let child = try store.category("Ammo")
        try set(parent, to: "wholesale-clubs")
        try set(child, to: "dining")
        var draft = CategoryDraft(parent)
        draft.type = .income
        #expect(draft.ownRewardsAs == nil)
        try store.catalog.update(parent, to: draft)
        #expect(parent.ownRewardsAs == nil)
        #expect(child.ownRewardsAs == nil)
        #expect(child.rewardsAs == nil)
    }

    // MARK: The Reward categories screen

    @Test func theMapListsEveryRewardCategoryWithTheCategoriesThatCountAsIt() throws {
        try set(try store.category("Products"), to: "groceries")
        try set(try store.category("Food & Beverage"), to: "dining")
        let map = try rewards.map()
        #expect(map.map(\.reward) == RewardCategory.fixed)
        let dining = try #require(map.first { $0.reward.id == "dining" })
        #expect(dining.categories.map(\.name) == ["Food & Beverage", "Café", "Restaurants"])
        let groceries = try #require(map.first { $0.reward.id == "groceries" })
        #expect(groceries.categories.map(\.name) == ["Products"])
        let everythingElse = try #require(map.last)
        #expect(everythingElse.reward == .everythingElse)
        #expect(everythingElse.categories.contains { $0.name == "Education" })
        #expect(!everythingElse.categories.contains { $0.isLocked })
        #expect(map.allSatisfy { entry in entry.categories.allSatisfy { $0.type == .expense } })
    }

    @Test func anOwnRewardCategoryCanBeAddedRenamedAndPickedForACategory() throws {
        let pets = try rewards.add(named: " Pet stores ")
        #expect(pets.name == "Pet stores")
        try set(try store.category("Pets"), to: pets.key)
        try rewards.rename(pets, to: "Pet shops")
        let map = try rewards.map()
        #expect(map.count == RewardCategory.fixed.count + 1)
        // An own Reward category comes before Everything else, which stays last.
        let own = map[map.count - 2]
        #expect(own.reward == RewardCategory(id: pets.key, name: "Pet shops", isOwn: true))
        #expect(own.categories.map(\.name) == ["Pets"])
        #expect(try rewards.all().contains(own.reward))
    }

    @Test func anOwnRewardCategoryNeedsAFreshName() throws {
        #expect(throws: RewardCategoryError.nameRequired) { try rewards.add(named: "  ") }
        #expect(throws: RewardCategoryError.nameTaken) { try rewards.add(named: "dining") }
        let pets = try rewards.add(named: "Pet stores")
        #expect(throws: RewardCategoryError.nameTaken) { try rewards.add(named: "PET STORES") }
        try rewards.rename(pets, to: "pet stores")
        #expect(pets.name == "pet stores")
    }

    @Test func deletingAnOwnRewardCategorySendsItsCategoriesBackToEverythingElse() throws {
        let pets = try rewards.add(named: "Pet stores")
        let parent = try store.category("Shopping")
        let child = try store.category("Books")
        let other = try store.category("Pets")
        try set(parent, to: "department-stores")
        try set(child, to: pets.key)
        try set(other, to: pets.key)
        try rewards.delete(pets)
        #expect(other.rewardsAs == RewardCategory.everythingElse.id)
        #expect(child.rewardsAs == RewardCategory.everythingElse.id)
        #expect(parent.rewardsAs == "department-stores")
        #expect(try rewards.map().count == RewardCategory.fixed.count)
    }

    // MARK: The one-time prefill

    @Test func thePrefillSetsTheDefaultTreesCategoriesByName() throws {
        try RewardsPrefill.prefillIfNeeded(in: store.context)
        #expect(try store.category("Food & Beverage").ownRewardsAs == "dining")
        #expect(try store.category("Café").ownRewardsAs == "dining")
        #expect(try store.category("Products").ownRewardsAs == "groceries")
        #expect(try store.category("Petrol").ownRewardsAs == "gas")
        #expect(try store.category("Parking Fees").ownRewardsAs == "transit")
        #expect(try store.category("Apps").ownRewardsAs == "streaming")
        #expect(try store.category("Pharmacy").ownRewardsAs == "drugstores")
        #expect(try store.category("Internet Bill").ownRewardsAs == "phone-internet")
        #expect(try store.category("Valet/Trash Bill").ownRewardsAs == "utilities")
        #expect(try store.category("Footwear").ownRewardsAs == "department-stores")
        #expect(try store.category("Education").ownRewardsAs == nil)
        #expect(try store.category("Bills & Utilities").rewardsAs == RewardCategory.everythingElse.id)
    }

    @Test func thePrefillNeverOverwritesAChoiceTheUserMade() throws {
        try set(try store.category("Products"), to: "wholesale-clubs")
        try RewardsPrefill.prefillIfNeeded(in: store.context)
        #expect(try store.category("Products").ownRewardsAs == "wholesale-clubs")
    }

    @Test func thePrefillRunsOnceAndChangesNothingOnASecondLaunch() throws {
        try RewardsPrefill.prefillIfNeeded(in: store.context)
        let cafe = try store.category("Café")
        try set(cafe, to: nil)
        try RewardsPrefill.prefillIfNeeded(in: store.context)
        #expect(cafe.ownRewardsAs == nil)
        #expect(!store.context.hasChanges)
    }

    @Test func theStoreIsPrefilledWhenItOpens() throws {
        let container = try StoreOpening.open(inMemory: true)
        let products = try #require(
            try container.mainContext.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Products" }
        )
        #expect(products.rewardsAs == "groceries")
    }
}
