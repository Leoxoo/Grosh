import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Rates the user enters: a Custom card's own, and a linked Card's Edited rates, which take the catalog's place for that
/// Card alone while every rate the user left alone keeps following the catalog the app ships (ADR-0014).
@MainActor
@Suite(.namedInTheLog)
struct EnteredRateTests {
    private let store: TestStore
    private let catalog: RewardsCatalog

    init() throws {
        store = try TestStore()
        catalog = try RewardsCatalogFixture.catalog()
    }

    private func customCard() throws -> Card {
        try store.context.addCard("Local Bank Card", paidFrom: store.checking)
    }

    private func linkedCard(_ id: String) throws -> Card {
        var draft = CardDraft.new(from: try #require(catalog.card(id)))
        draft.payingWallet = store.checking
        return try Card.create(draft, in: store.context)
    }

    private func rates(_ card: Card, in catalog: RewardsCatalog? = nil, own: [RewardCategory] = []) -> [CardRate] {
        CardRewards(of: card, in: catalog ?? self.catalog).rates(on: TestStore.today, own: own)
    }

    private func entered(_ reward: String, _ rate: Double?) -> EnteredRate {
        EnteredRate(reward: reward, rate: rate)
    }

    // MARK: Custom cards

    @Test func aCustomCardCanBeGivenAnyNumberOfRates() throws {
        let card = try customCard()
        try card.saveRate(in: catalog, entered("dining", 4), replacing: nil)
        try card.saveRate(in: catalog, entered("groceries", 2), replacing: nil)
        try card.saveRate(in: catalog, entered("everything-else", 1), replacing: nil)
        let shown = rates(card)
        #expect(shown.map(\.reward.id) == ["dining", "groceries", "everything-else"])
        #expect(shown.map(\.effectiveRate) == [4, 2, 1])
        #expect(shown.allSatisfy { $0.multiplier == nil && $0.rule == nil && !$0.isEdited })
    }

    @Test func aRateKeepsItsCapAndDates() throws {
        let card = try customCard()
        var rate = entered("gas", 5)
        rate.capAmount = 1500
        rate.capPeriod = .quarter
        rate.from = day(2026, 10, 1)
        rate.to = day(2026, 12, 31)
        try card.saveRate(in: catalog, rate, replacing: nil)
        let shown = try #require(rates(card).first)
        #expect(shown.cap == RateCap(amount: 1500, period: .quarter))
        #expect(shown.validFrom == day(2026, 10, 1))
        #expect(shown.validTo == day(2026, 12, 31))
        #expect(card.enteredRates == [rate])
    }

    @Test func aRateOutsideItsDatesIsNotShown() throws {
        let card = try customCard()
        var rate = entered("gas", 5)
        rate.to = day(2026, 9, 30)
        try card.saveRate(in: catalog, rate, replacing: nil)
        #expect(rates(card).isEmpty)
    }

    @Test func aRateCanBeEditedAndRemoved() throws {
        let card = try customCard()
        try card.saveRate(in: catalog, entered("dining", 4), replacing: nil)
        try card.saveRate(in: catalog, entered("travel", 3), replacing: "dining")
        #expect(rates(card).map(\.reward.id) == ["travel"])
        try card.removeRate(for: "travel", in: catalog)
        #expect(rates(card).isEmpty)
        #expect(card.enteredRates.isEmpty)
    }

    @Test func aRateNeedsARateAboveZeroAFreeCategoryAndDatesInOrder() throws {
        let card = try customCard()
        #expect(throws: EnteredRateError.rateOutOfRange) { try card.saveRate(in: catalog, entered("dining", 0), replacing: nil) }
        #expect(throws: EnteredRateError.rateOutOfRange) { try card.saveRate(in: catalog, entered("dining", nil), replacing: nil) }
        try card.saveRate(in: catalog, entered("dining", 3), replacing: nil)
        #expect(throws: EnteredRateError.categoryTaken) { try card.saveRate(in: catalog, entered("dining", 4), replacing: nil) }
        var capped = entered("gas", 2)
        capped.capAmount = 0
        #expect(throws: EnteredRateError.capOutOfRange) { try card.saveRate(in: catalog, capped, replacing: nil) }
        var dated = entered("gas", 2)
        dated.from = day(2026, 12, 1)
        dated.to = day(2026, 11, 1)
        #expect(throws: EnteredRateError.datesOutOfOrder) { try card.saveRate(in: catalog, dated, replacing: nil) }
    }

    @Test func pointsOrMilesMakesARateAMultiplierWorthItsPointValue() throws {
        let card = try customCard()
        try card.setRewardKind(.points)
        var draft = CardDraft(card, catalog: catalog)
        #expect(draft.offersPointValue)
        draft.pointValueCents = 1.25
        try card.update(with: draft)
        try card.saveRate(in: catalog, entered("dining", 4), replacing: nil)
        let shown = try #require(rates(card).first)
        #expect(shown.multiplier == 4)
        #expect(shown.effectiveRate == 5)
    }

    @Test func aCustomCardEarnsOnAnOwnRewardCategory() throws {
        let pets = try RewardCategories(context: store.context).add(named: "Pet stores")
        let card = try customCard()
        try card.saveRate(in: catalog, entered(pets.key, 5), replacing: nil)
        let own = [RewardCategory(pets)]
        #expect(rates(card, own: own).map(\.reward) == own)
        #expect(rates(card).isEmpty)
    }

    // MARK: Edited rates on a linked Card

    @Test func changingACatalogRateMakesAnEditedRate() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("dining", 5.25), replacing: nil)
        let shown = rates(card)
        #expect(shown.map(\.reward.id) == ["dining", "groceries", "everything-else"])
        #expect(shown.map(\.effectiveRate) == [5.25, 3, 1])
        #expect(shown.map(\.isEdited) == [true, false, false])
        #expect(shown[0].rule == nil)
    }

    @Test func aRateCanBeAddedToAndRemovedFromALinkedCard() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("gas", 2), replacing: nil)
        try card.removeRate(for: "groceries", in: catalog)
        let shown = rates(card)
        #expect(shown.map(\.reward.id) == ["dining", "gas", "everything-else"])
        #expect(shown.first { $0.reward.id == "gas" }?.isEdited == true)
        #expect(card.enteredRates.contains(entered("groceries", nil)))
    }

    @Test func resetToCatalogBringsBackTheCatalogsRate() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("dining", 5.25), replacing: nil)
        try card.removeRate(for: "groceries", in: catalog)
        try card.resetRate(for: "dining")
        try card.resetRate(for: "groceries")
        #expect(rates(card).map(\.effectiveRate) == [3, 3, 1])
        #expect(rates(card).allSatisfy { !$0.isEdited })
        #expect(card.enteredRates.isEmpty)
    }

    @Test func removingAnAddedRateLeavesNothingBehind() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("gas", 2), replacing: nil)
        try card.removeRate(for: "gas", in: catalog)
        #expect(card.enteredRates.isEmpty)
    }

    @Test func anEditedRateStaysWhenANewerCatalogChangesThatCardAndTheOthersFollowIt() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("dining", 5.25), replacing: nil)
        var savory = RewardsCatalogFixture.savory
        savory["rules"] = [
            RewardsCatalogFixture.rule(["dining"], 4), RewardsCatalogFixture.rule(["groceries"], 3.5),
            RewardsCatalogFixture.rule(["everything-else"], 1.5),
        ]
        let newer = try RewardsCatalogFixture.catalog(cards: [savory])
        #expect(rates(card, in: newer).map(\.effectiveRate) == [5.25, 3.5, 1.5])
        #expect(rates(card, in: newer).map(\.isEdited) == [true, false, false])
    }

    @Test func changingCatalogCardRemovesTheOldOnesEditedRates() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("dining", 5.25), replacing: nil)
        var draft = CardDraft(card, catalog: catalog)
        #expect(draft.editedRatesRemovedByChange == 1)
        draft.catalogCard = try #require(catalog.card("test-voyager-points"))
        try card.update(with: draft)
        #expect(card.enteredRates.isEmpty)
        #expect(rates(card).map(\.effectiveRate) == [3, 2, 1])
    }

    @Test func unlinkingKeepsTheRatesTheUserEnteredAndDropsWhatTheyRemoved() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("dining", 5.25), replacing: nil)
        try card.removeRate(for: "groceries", in: catalog)
        try card.link(to: nil)
        #expect(card.enteredRates == [entered("dining", 5.25)])
        #expect(rates(card).map(\.reward.id) == ["dining"])
    }

    @Test func movingAnEditedCatalogRateToAnotherCategoryRemovesTheCatalogsFromTheOld() throws {
        let card = try linkedCard("test-savory-cash")
        try card.saveRate(in: catalog, entered("gas", 3), replacing: "dining")
        #expect(rates(card).map(\.reward.id) == ["groceries", "gas", "everything-else"])
        #expect(card.enteredRates.contains(entered("dining", nil)))
    }

    @Test func aCatalogRateStartsTheFormAtTheSameEffectiveRateInTheCardsUnit() throws {
        let card = try linkedCard("test-voyager-points")
        var draft = CardDraft(card, catalog: catalog)
        draft.pointValueCents = 2
        try card.update(with: draft)
        let row = try #require(CardRewards(of: card, in: catalog).editable(on: TestStore.today).first { $0.reward.id == "dining" })
        let start = EnteredRate(editing: row, earnsPoints: true, pointValueCents: 2)
        #expect(start.rate == 3)
        #expect(EnteredRate(editing: row, earnsPoints: false, pointValueCents: 2).rate == 6)
        #expect(start.capAmount == nil && start.from == nil && start.to == nil)
    }

    @Test func unlinkingAPointsCardKeepsItsRatesInPoints() throws {
        let card = try linkedCard("test-voyager-points")
        try card.saveRate(in: catalog, entered("dining", 4), replacing: nil)
        try card.link(to: nil)
        #expect(CardRewards(of: card, in: catalog).rewardKind == .points)
        #expect(rates(card).first?.multiplier == 4)
    }

    @Test func deletingAnOwnRewardCategoryRemovesTheRatesEnteredForIt() throws {
        let rewards = RewardCategories(context: store.context)
        let pets = try rewards.add(named: "Pet stores")
        let card = try customCard()
        try card.saveRate(in: catalog, entered(pets.key, 5), replacing: nil)
        try card.saveRate(in: catalog, entered("dining", 2), replacing: nil)
        try rewards.delete(pets)
        #expect(card.enteredRates == [entered("dining", 2)])
    }

    @Test func aLinkedCardsKindIsTheCatalogs() throws {
        let card = try linkedCard("test-voyager-points")
        try card.setRewardKind(.cashback)
        #expect(CardRewards(of: card, in: catalog).rewardKind == .points)
    }
}
