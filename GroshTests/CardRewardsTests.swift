import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A Card linked to the rewards catalog and what its page shows it earns: one rate per Reward category, best first,
/// Everything else last. A linked Card follows the catalog the app ships, and keeps its entry's last rates when a newer
/// catalog no longer has it (ADR-0013).
@MainActor
@Suite(.namedInTheLog)
struct CardRewardsTests {
    private let store: TestStore
    private let catalog: RewardsCatalog

    init() throws {
        store = try TestStore()
        catalog = try RewardsCatalogFixture.catalog()
    }

    private func entry(_ id: String) throws -> CatalogCard {
        try #require(catalog.card(id))
    }

    /// A new Card linked to the catalog entry `id`, as Add Card makes it after the user picks that entry.
    private func linkedCard(_ id: String) throws -> Card {
        var draft = CardDraft.new(from: try entry(id))
        draft.payingWallet = store.checking
        return try Card.create(draft, in: store.context)
    }

    private func rates(_ card: Card, in catalog: RewardsCatalog? = nil) -> [CardRate] {
        CardRewards(of: card, in: catalog ?? self.catalog).rates(on: TestStore.today)
    }

    @Test func pickingACatalogEntryPrefillsTheNameAndLinksTheCard() throws {
        let card = try linkedCard("test-savory-cash")
        #expect(card.name == "Savory Cash")
        #expect(card.catalogCardID == "test-savory-cash")
        #expect(CardRewards(of: card, in: catalog).entry?.issuer == "Test Bank")
    }

    @Test func aCardShowsItsFixedRatesBestFirstAndEverythingElseLast() throws {
        let shown = rates(try linkedCard("test-savory-cash"))
        #expect(shown.map(\.reward.id) == ["dining", "groceries", "everything-else"])
        #expect(shown.map(\.effectiveRate) == [3, 3, 1])
        #expect(shown.allSatisfy { $0.multiplier == nil })
        #expect(shown[0].rule.capAmount == 2500)
        #expect(shown[0].rule.evidence.quote == "Earn 3% cash back on dining and at grocery stores.")
    }

    @Test func rotatingPaidWithMerchantTierAndOpenDateRatesAreLeftOut() throws {
        let shown = rates(try linkedCard("test-savory-cash"))
        #expect(!shown.contains { $0.reward.id == "gas" || $0.reward.id == "online-shopping" })
        #expect(shown.first { $0.reward.id == "everything-else" }?.effectiveRate == 1)
        #expect(shown.first { $0.reward.id == "dining" }?.effectiveRate == 3)
        #expect(shown.first { $0.reward.id == "groceries" }?.effectiveRate == 3)
    }

    @Test func aPointsCardShowsItsMultiplierAndARateThatEndedIsLeftOut() throws {
        let shown = rates(try linkedCard("test-voyager-points"))
        #expect(shown.map(\.reward.id) == ["dining", "travel", "everything-else"])
        #expect(shown.map(\.multiplier) == [3, 2, 1])
        #expect(shown.map(\.effectiveRate) == [3, 2, 1])
        #expect(shown[0].rule.requires == ["activation"])
    }

    @Test func aPercentRateOnAPointsCardIsAlreadyAnEffectiveRate() throws {
        var voyager = RewardsCatalogFixture.voyager
        voyager["rules"] = [RewardsCatalogFixture.rule(["groceries"], 2), RewardsCatalogFixture.rule(["dining"], 3, unit: "per-dollar")]
        let catalog = try RewardsCatalogFixture.catalog(cards: [voyager])
        var draft = CardDraft.new(from: try #require(catalog.card("test-voyager-points")))
        draft.payingWallet = store.checking
        draft.pointValueCents = 0.5
        let shown = rates(try Card.create(draft, in: store.context), in: catalog)
        #expect(shown.map(\.reward.id) == ["groceries", "dining"])
        #expect(shown.map(\.multiplier) == [nil, 3])
        #expect(shown.map(\.effectiveRate) == [2, 1.5])
    }

    @Test func pointValueChangesAPointsCardsEffectiveRate() throws {
        let card = try linkedCard("test-voyager-points")
        var draft = CardDraft(card, catalog: catalog)
        draft.pointValueCents = 1.5
        try card.update(with: draft)
        let shown = rates(card)
        #expect(shown.map(\.multiplier) == [3, 2, 1])
        #expect(shown.map(\.effectiveRate) == [4.5, 3, 1.5])
    }

    @Test func pointValueDoesntChangeACashBackCard() throws {
        let card = try linkedCard("test-savory-cash")
        var draft = CardDraft(card, catalog: catalog)
        draft.pointValueCents = 2
        try card.update(with: draft)
        #expect(rates(card).map(\.effectiveRate) == [3, 3, 1])
    }

    @Test func pointValueIsOneCentUntilChangedAndMustBeAboveZero() throws {
        let card = try linkedCard("test-old-miles")
        #expect(card.pointValueCents == 1)
        var draft = CardDraft(card, catalog: catalog)
        draft.pointValueCents = 0
        #expect(throws: CardRuleError.pointValueOutOfRange) { try card.update(with: draft) }
    }

    @Test func anExistingCardCanBeLinkedChangedToAnotherEntryAndUnlinked() throws {
        let card = try store.context.addCard("My Visa", paidFrom: store.checking)
        #expect(CardRewards(of: card, in: catalog).entry == nil)
        #expect(rates(card).isEmpty)

        try card.link(to: try entry("test-savory-cash"))
        #expect(card.catalogCardID == "test-savory-cash")
        #expect(card.name == "My Visa")

        var draft = CardDraft(card, catalog: catalog)
        draft.catalogCard = try entry("test-voyager-points")
        try card.update(with: draft)
        #expect(card.catalogCardID == "test-voyager-points")
        #expect(card.name == "My Visa")
        #expect(rates(card).first?.multiplier == 3)

        draft = CardDraft(card, catalog: catalog)
        draft.catalogCard = nil
        try card.update(with: draft)
        #expect(card.catalogCardID == nil)
        #expect(card.catalogSnapshot == nil)
        #expect(rates(card).isEmpty)
    }

    @Test func aLinkedCardFollowsTheCatalogTheAppShips() throws {
        let card = try linkedCard("test-savory-cash")
        var savory = RewardsCatalogFixture.savory
        savory["rules"] = [RewardsCatalogFixture.rule(["dining"], 4), RewardsCatalogFixture.rule(["everything-else"], 1.5)]
        let newer = try RewardsCatalogFixture.catalog(cards: [savory])
        #expect(rates(card, in: newer).map(\.effectiveRate) == [4, 1.5])
        #expect(!CardRewards(of: card, in: newer).isNoLongerInCatalog)
    }

    @Test func anEntryANewerCatalogNoLongerHasKeepsItsLastRatesAndSaysSo() throws {
        let card = try linkedCard("test-savory-cash")
        let without = try RewardsCatalogFixture.catalog(cards: [RewardsCatalogFixture.voyager])
        let rewards = CardRewards(of: card, in: without)
        #expect(rewards.isNoLongerInCatalog)
        #expect(rewards.entry?.name == "Savory Cash")
        #expect(rates(card, in: without).map(\.reward.id) == ["dining", "groceries", "everything-else"])
    }

    @Test func openingTheStoreKeepsTheRatesTheEntryLastHad() throws {
        let card = try linkedCard("test-savory-cash")
        var savory = RewardsCatalogFixture.savory
        savory["rules"] = [RewardsCatalogFixture.rule(["dining"], 4)]
        try Card.keepCatalogEntries(from: try RewardsCatalogFixture.catalog(cards: [savory]), in: store.context)
        #expect(!store.context.hasChanges)
        let gone = try RewardsCatalogFixture.catalog(cards: [])
        #expect(rates(card, in: gone).map(\.effectiveRate) == [4])

        try Card.keepCatalogEntries(from: try RewardsCatalogFixture.catalog(cards: [savory]), in: store.context)
        #expect(!store.context.hasChanges)
    }
}
