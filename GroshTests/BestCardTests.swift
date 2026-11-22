import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Best Card: each Reward category's tile shows its Go-to card, or else the unarchived Card that earns the most on it,
/// with what that rate Needs. Rates compete as if what they Need is done, and nothing counts what was earned
/// (ADR-0016).
@MainActor
@Suite(.namedInTheLog)
struct BestCardTests {
    private let store: TestStore
    private let catalog: RewardsCatalog

    init() throws {
        store = try TestStore()
        catalog = try RewardsCatalogFixture.catalog()
    }

    /// A Card linked to the catalog entry `id`, as Add Card makes it.
    private func linked(_ name: String, to id: String, pointValue: Double = 1) throws -> Card {
        var draft = CardDraft.new(from: try #require(catalog.card(id)))
        draft.name = name
        draft.payingWallet = store.checking
        draft.pointValueCents = pointValue
        return try Card.create(draft, in: store.context)
    }

    /// A Custom card earning `rates` (percent, by Reward category).
    private func custom(_ name: String, _ rates: [String: Double]) throws -> Card {
        let card = try store.context.addCard(name, paidFrom: store.checking)
        for (reward, rate) in rates.sorted(by: { $0.key < $1.key }) {
            try card.saveRate(in: catalog, EnteredRate(reward: reward, rate: rate), replacing: nil)
        }
        return card
    }

    private func bestCard() throws -> BestCard {
        let cards = try store.context.fetch(Card.unarchived)
        return BestCard(cards: cards, catalog: catalog, own: [], on: TestStore.today, spending: { _ in [:] })
    }

    private func reward(_ id: String) throws -> RewardCategory {
        try #require(RewardCategory.fixed(id))
    }

    // MARK: Needs

    @Test func aPaidWithRateCompetesWithEveryRateAndSaysWhatItNeeds() throws {
        let savory = try linked("Savory", to: "test-savory-cash")
        let rewards = CardRewards(of: savory, in: catalog)

        let gas = try #require(rewards.rankedEarning(for: ["gas"], on: TestStore.today))
        #expect(gas.effectiveRate == 2)
        #expect(gas.needs == [.paysWith("Apple Pay")])

        let dining = try #require(rewards.rankedEarning(for: ["dining"], on: TestStore.today))
        #expect(dining.effectiveRate == 3)
        #expect(dining.needs.isEmpty)
    }

    @Test func theCardsPageStillListsAPaidWithRateApart() throws {
        let savory = try linked("Savory", to: "test-savory-cash")
        let page = CardRewards(of: savory, in: catalog).page(on: TestStore.today)
        #expect(page.earned.first { $0.reward == .everythingElse }?.effectiveRate == 1)
        #expect(page.conditional.contains { $0.rule?.paysWith == "Apple Pay" })
    }

    @Test func aRateTheBankAsksToActivateNeedsActivation() throws {
        let voyager = try linked("Voyager", to: "test-voyager-points")
        let dining = try #require(CardRewards(of: voyager, in: catalog).rankedEarning(for: ["dining"], on: TestStore.today))
        #expect(dining.effectiveRate == 3)
        #expect(dining.needs == [.activation])
    }

    @Test func theCardPickerRanksAPaidWithRateAndNamesWhatItNeeds() throws {
        let savory = try linked("Savory", to: "test-savory-cash")
        let plain = try custom("Plain", ["everything-else": 1.5])
        let order = CardEarning.ordered(
            [plain, savory], for: try store.category("Education"), in: catalog, own: [], on: TestStore.today,
            spending: { _ in [:] }
        )
        #expect(order.map(\.card.name) == ["Savory", "Plain"])
        #expect(order.map(\.detail) == ["Everything else · with Apple Pay", "Everything else"])
    }

    // MARK: Tiles

    @Test func aTileShowsTheCardThatEarnsTheMostWithEqualRatesInTheUsersOrder() throws {
        _ = try custom("First", ["groceries": 4])
        _ = try custom("Second", ["groceries": 4])
        _ = try custom("Third", ["groceries": 2])
        let tile = try bestCard().tile(for: try reward("groceries"))
        #expect(tile.shown?.card.name == "First")
        #expect(tile.shown?.earning.effectiveRate == 4)
        #expect(!tile.isGoTo)
        #expect(!tile.isBeaten)
    }

    @Test func aTileNoCardEarnsOnShowsNoCard() throws {
        _ = try store.context.addCard("Debit", kind: .debit, paidFrom: store.checking)
        #expect(try bestCard().tile(for: try reward("hotels")).shown == nil)
    }

    @Test func anArchivedCardIsNeverShown() throws {
        let archived = try custom("Old", ["gas": 9])
        try archived.archive()
        _ = try custom("Current", ["gas": 2])
        #expect(try bestCard().tile(for: try reward("gas")).shown?.card.name == "Current")
    }

    @Test func aRateThatNeedsApplePayCanBeTheTilesCardFlaggedWithIt() throws {
        _ = try linked("Savory", to: "test-savory-cash")
        _ = try custom("Plain", ["gas": 1.5])
        let tile = try bestCard().tile(for: try reward("gas"))
        #expect(tile.shown?.card.name == "Savory")
        #expect(tile.shown?.earning.needs == [.paysWith("Apple Pay")])
    }

    @Test func aStoreRateIsListedWithItsStoreButNeverTheTilesCard() throws {
        let savory = try linked("Savory", to: "test-savory-cash")
        _ = try custom("Shopper", ["online-shopping": 3])
        let best = try bestCard()
        let online = try reward("online-shopping")
        #expect(best.tile(for: online).shown?.card.name == "Shopper")

        let rows = best.rows(for: online)
        #expect(rows.map(\.card.name) == ["Savory", "Shopper", "Savory"])
        #expect(rows.map(\.effectiveRate) == [5, 3, 2])
        #expect(rows.map(\.needs) == [[.store(["Amazon"])], [], [.paysWith("Apple Pay")]])
        #expect(rows.first?.card == savory)
    }

    // MARK: Go-to card

    @Test func theGoToCardTakesTheTileFlaggedWhenAnotherEarnsMoreAndNeedsNothingMore() throws {
        let low = try custom("Low", ["dining": 2])
        _ = try custom("Higher", ["dining": 3])
        _ = try custom("High", ["dining": 4])
        try low.makeGoTo(for: "dining")
        let tile = try bestCard().tile(for: try reward("dining"))
        #expect(tile.shown?.card.name == "Low")
        #expect(tile.isGoTo)
        #expect(tile.beatenBy?.card.name == "High")
    }

    @Test func aCardThatNeedsMoreThanTheGoToCardDoesntFlagIt() throws {
        let plain = try custom("Plain", ["gas": 1.5])
        _ = try linked("Savory", to: "test-savory-cash")
        try plain.makeGoTo(for: "gas")
        let tile = try bestCard().tile(for: try reward("gas"))
        #expect(tile.shown?.card.name == "Plain")
        #expect(!tile.isBeaten)
    }

    @Test func aCardIsTheGoToForOneRewardCategoryInPlaceOfAnother() throws {
        let first = try custom("First", ["dining": 2])
        let second = try custom("Second", ["dining": 3])
        try first.makeGoTo(for: "dining")
        try second.makeGoTo(for: "dining")
        #expect(first.goToRewards.isEmpty)
        #expect(second.goToRewards == ["dining"])
        try second.removeGoTo(for: "dining")
        #expect(try bestCard().tile(for: try reward("dining")).isGoTo == false)
    }

    @Test func anArchivedGoToCardGivesWayToTheCardThatEarnsTheMost() throws {
        let goTo = try custom("Go-to", ["dining": 4])
        _ = try custom("Other", ["dining": 2])
        try goTo.makeGoTo(for: "dining")
        try goTo.archive()
        let tile = try bestCard().tile(for: try reward("dining"))
        #expect(tile.shown?.card.name == "Other")
        #expect(!tile.isGoTo)
    }

    @Test func theRowsMarkTheGoToCard() throws {
        let goTo = try custom("Go-to", ["dining": 2])
        _ = try custom("Other", ["dining": 4])
        try goTo.makeGoTo(for: "dining")
        let rows = try bestCard().rows(for: try reward("dining"))
        #expect(rows.map(\.card.name) == ["Other", "Go-to"])
        #expect(rows.map(\.isGoTo) == [false, true])
    }

    // MARK: Which tiles, in what order

    private let own = RewardCategory(id: "pets", name: "Pet stores", isOwn: true)

    @Test func beforeTheUserChoosesTheStarterTilesShowThenTheirOwnThenEverythingElse() {
        let listed = RewardCategory.listed(own: [own])
        let shown = BestCardLayout.read("", listed: listed).shown(listed).map(\.id)
        #expect(shown == [
            "dining", "groceries", "gas", "travel", "online-shopping", "streaming", "drugstores", "transit", "pets",
            "everything-else",
        ])
    }

    @Test func hidingMovingAndKeepingALayout() throws {
        let listed = RewardCategory.listed(own: [])
        var layout = BestCardLayout.read("", listed: listed)
        layout = layout.toggled("groceries", in: listed)
        layout = layout.toggled("hotels", in: listed)
        let arranged = layout.arranged(listed).map(\.reward.id)
        let hotels = try #require(arranged.firstIndex(of: "hotels"))
        layout = layout.moved(from: IndexSet(integer: hotels), to: 0, in: listed)

        let kept = BestCardLayout.read(layout.stored, listed: listed)
        #expect(kept == layout)
        #expect(Array(kept.shown(listed).map(\.id).prefix(3)) == ["hotels", "dining", "gas"])
        #expect(!kept.shown(listed).map(\.id).contains("groceries"))
        #expect(kept.arranged(listed).count == listed.count)
    }

    @Test func aRewardCategoryAddedLaterShowsAtTheEndAndADeletedOneGoes() {
        let before = RewardCategory.listed(own: [])
        let layout = BestCardLayout.read("", listed: before).toggled("dining", in: before)
        let added = RewardCategory.listed(own: [own])
        #expect(layout.shown(added).last?.id == "pets")
        let withOwn = layout.toggled("hotels", in: added)
        #expect(!withOwn.shown(before).contains { $0.id == "pets" })
    }

    @Test func aLayoutThatCantBeReadStartsOver() {
        let listed = RewardCategory.listed(own: [])
        #expect(BestCardLayout.read("not json", listed: listed) == BestCardLayout.starting(listed))
    }

    // MARK: Search

    @Test func searchFindsRewardCategoriesByNameOrByTheUsersCategoriesCountingAsThem() throws {
        try RewardCategories(context: store.context).setRewardsAs(of: try store.category("Café"), to: ["dining"])
        let listed = RewardCategory.listed(own: [])
        let map = RewardCategories.map(of: try store.context.fetch(FetchDescriptor<Grosh.Category>()), own: [])
        let names = Dictionary(uniqueKeysWithValues: map.map { ($0.reward.id, $0.categories.map(\.name)) })
        #expect(BestCardSearch.matches("cafe", in: listed, categoryNames: names).map(\.id) == ["dining"])
        #expect(BestCardSearch.matches("GROC", in: listed, categoryNames: names).map(\.id) == ["groceries"])
        #expect(BestCardSearch.matches("  ", in: listed, categoryNames: names).count == listed.count)
    }
}
