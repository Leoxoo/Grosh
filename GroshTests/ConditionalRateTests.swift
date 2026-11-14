import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The catalog's rules that depend on more than a purchase's category: rotating quarters earned between their dates,
/// a rate on Your choice, a rate on the top-spend category, rates limited to a way of paying or to
/// merchants (shown, never earned), and Bonuses add up.
@MainActor
@Suite(.namedInTheLog)
struct ConditionalRateTests {
    private typealias Fixture = RewardsCatalogFixture
    private let store: TestStore

    init() throws {
        store = try TestStore()
    }

    private static func quarter(_ categories: [String], from: String, to: String) -> [String: Any?] {
        Fixture.rule(categories, 5, selection: "rotating", capAmount: 1500, capPeriod: "quarter", requires: ["activation"],
                     validFrom: from, validTo: to)
    }

    /// A Freedom Flex–like card: 1% base, 3% Dining and Drugstores, 5% rotating quarters, its bonuses adding up unless
    /// `stacks` is false.
    private static func flex(stacks: Bool = true, quarters: Bool = true) -> [String: Any?] {
        var card = Fixture.card("test-flex", "Flex", issuer: "Test Bank", kind: "cashback", rules: [
            Fixture.rule(["everything-else"], 1), Fixture.rule(["dining"], 3), Fixture.rule(["drugstores"], 3),
            Fixture.rule([], 5, selection: "rotating", requires: ["activation"]),
        ] + (quarters ? [
            quarter(["groceries", "dining"], from: "2026-10-01", to: "2026-12-31"),
            quarter(["groceries", "streaming"], from: "2027-01-01", to: "2027-03-31"),
            quarter(["gas"], from: "2026-07-01", to: "2026-09-30"),
        ] : []))
        card["bonusesStack"] = stacks
        return card
    }

    private static let customized = Fixture.card("test-customized", "Customized", issuer: "Test Bank", kind: "cashback", rules: [
        Fixture.rule(["everything-else"], 1), Fixture.rule(["groceries"], 2),
        Fixture.rule(["gas", "online-shopping", "dining", "travel"], 3, selection: "choose"),
    ])

    private static let topSpend = Fixture.card("test-top", "Top", issuer: "Test Bank", kind: "cashback", rules: [
        Fixture.rule(["everything-else"], 1),
        Fixture.rule(["dining", "groceries", "gas"], 5, selection: "top-spend", capAmount: 500, capPeriod: "cycle"),
    ])

    private func linked(_ card: [String: Any?], statementDay: Int? = nil) throws -> (Card, RewardsCatalog) {
        let catalog = try Fixture.catalog(cards: [card])
        var draft = CardDraft.new(from: try #require(catalog.cards.first))
        draft.payingWallet = store.checking
        if let statementDay {
            draft.hasStatementDate = true
            draft.statementDayChoice = statementDay
        }
        return (try Card.create(draft, in: store.context), catalog)
    }

    private func earning(
        _ card: Card, _ catalog: RewardsCatalog, _ reward: String, on day: CalendarDay = TestStore.today,
        spending: [String: Int] = [:]
    ) -> PurchaseEarning? {
        CardRewards(of: card, in: catalog).earning(for: reward, on: day, spending: spending)
    }

    // MARK: Rotating quarters

    @Test func eachCurrentOrComingQuarterIsShown() throws {
        let (card, catalog) = try linked(Self.flex())
        let page = CardRewards(of: card, in: catalog).page(on: TestStore.today)
        #expect(page.quarters.map(\.start) == ["2026-10-01", "2027-01-01"])
        #expect(page.quarters.map { $0.rewards.map(\.id) } == [["dining", "groceries"], ["groceries", "streaming"]])
        #expect(page.quarters.map(\.isCurrent) == [true, false])
        #expect(page.quarters.first?.rate.cap == RateCap(amount: 1500, period: .quarter, currencyCode: "USD"))
        #expect(page.rotatingWithoutQuarter == nil)
    }

    @Test func aQuarterIsEarnedBetweenItsDates() throws {
        let (card, catalog) = try linked(Self.flex(stacks: false))
        #expect(earning(card, catalog, "groceries")?.effectiveRate == 5)
        #expect(earning(card, catalog, "groceries")?.reward.id == "groceries")
        #expect(earning(card, catalog, "groceries", on: day(2027, 1, 15))?.effectiveRate == 5)
        #expect(earning(card, catalog, "streaming", on: day(2027, 1, 15))?.effectiveRate == 5)
        #expect(earning(card, catalog, "streaming")?.effectiveRate == 1)
        #expect(earning(card, catalog, "gas")?.effectiveRate == 1)
    }

    @Test func aRotatingRuleWithNoDatedQuarterIsShownAndNeverEarned() throws {
        let (card, catalog) = try linked(Self.flex(quarters: false))
        let page = CardRewards(of: card, in: catalog).page(on: TestStore.today)
        #expect(page.quarters.isEmpty)
        #expect(page.rotatingWithoutQuarter?.effectiveRate == 5)
        #expect(earning(card, catalog, "groceries")?.effectiveRate == 1)
    }

    // MARK: Bonuses add up

    @Test func bonusesAddUpWhenTheCardSaysSo() throws {
        let (card, catalog) = try linked(Self.flex())
        #expect(earning(card, catalog, "dining")?.effectiveRate == 7)
        #expect(earning(card, catalog, "groceries")?.effectiveRate == 5)
        #expect(earning(card, catalog, "drugstores")?.effectiveRate == 3)
        #expect(earning(card, catalog, "travel")?.effectiveRate == 1)
        #expect(earning(card, catalog, "travel")?.reward == .everythingElse)
    }

    @Test func otherwiseAPurchaseEarnsTheBestSingleRate() throws {
        let (card, catalog) = try linked(Self.flex(stacks: false))
        #expect(earning(card, catalog, "dining")?.effectiveRate == 5)
        #expect(earning(card, catalog, "drugstores")?.effectiveRate == 3)
    }

    @Test func theCardsPageShowsWhatEachCategoryEarnsAddedUp() throws {
        let (card, catalog) = try linked(Self.flex())
        let earned = CardRewards(of: card, in: catalog).page(on: TestStore.today).earned
        #expect(earned.map(\.reward.id) == ["dining", "groceries", "drugstores", "everything-else"])
        #expect(earned.map(\.effectiveRate) == [7, 5, 3, 1])
        let dining = try #require(earned.first)
        #expect(dining.parts.map(\.adds) == [1, 2, 4])
        #expect(dining.parts.map { $0.quarter?.start } == [nil, nil, "2026-10-01"])
        let january = CardRewards(of: card, in: catalog).page(on: day(2027, 1, 15)).earned
        #expect(january.map(\.reward.id) == ["groceries", "streaming", "dining", "drugstores", "everything-else"])
        #expect(january.map(\.effectiveRate) == [5, 5, 3, 3, 1])
    }

    @Test func withoutAddingUpThePageShowsTheBestSingleRate() throws {
        let (card, catalog) = try linked(Self.flex(stacks: false))
        let dining = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).earned.first)
        #expect(dining.reward.id == "dining")
        #expect(dining.effectiveRate == 5)
        #expect(dining.parts.map(\.adds) == [5])
    }

    // MARK: Your choice

    @Test func aChosenRateEarnsOnlyOnYourChoice() throws {
        let (card, catalog) = try linked(Self.customized)
        let choice = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first)
        #expect(!choice.isTopSpend)
        #expect(choice.chosen.isEmpty)
        #expect(choice.options.map(\.id) == ["dining", "gas", "travel", "online-shopping"])
        #expect(earning(card, catalog, "gas")?.effectiveRate == 1)

        try card.setYourChoice(["gas"], for: choice.key, in: catalog)
        #expect(earning(card, catalog, "gas")?.effectiveRate == 3)
        #expect(earning(card, catalog, "dining")?.effectiveRate == 1)
        #expect(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first?.chosen.map(\.id) == ["gas"])
    }

    @Test func yourChoiceIsOneOfTheRulesCategoriesUpToItsPicks() throws {
        let (card, catalog) = try linked(Self.customized)
        let key = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first?.key)
        #expect(throws: YourChoiceError.notAnOption) { try card.setYourChoice(["groceries"], for: key, in: catalog) }
        #expect(throws: YourChoiceError.tooMany) { try card.setYourChoice(["gas", "dining"], for: key, in: catalog) }
        try card.setYourChoice([], for: key, in: catalog)
        #expect(earning(card, catalog, "gas")?.effectiveRate == 1)
    }

    // MARK: Top spend

    @Test func aTopSpendRateEarnsOnTheCategoryTheCardWasUsedMostFor() throws {
        let (card, catalog) = try linked(Self.topSpend)
        let spending = ["groceries": 30_00, "dining": 50_00, "travel": 900_00]
        #expect(earning(card, catalog, "dining", spending: spending)?.effectiveRate == 5)
        #expect(earning(card, catalog, "groceries", spending: spending)?.effectiveRate == 1)
        let choice = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today, spending: spending).choices.first)
        #expect(choice.isTopSpend)
        #expect(choice.topSpend?.id == "dining")
        #expect(earning(card, catalog, "dining")?.effectiveRate == 1)
    }

    @Test func yourChoiceTakesTheTopSpendCategorysPlace() throws {
        let (card, catalog) = try linked(Self.topSpend)
        let key = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first?.key)
        try card.setYourChoice(["groceries"], for: key, in: catalog)
        let spending = ["dining": 50_00]
        #expect(earning(card, catalog, "groceries", spending: spending)?.effectiveRate == 5)
        #expect(earning(card, catalog, "dining", spending: spending)?.effectiveRate == 1)
    }

    @Test func topSpendIsCountedFromTheCardsCurrentPeriodOnly() throws {
        let rewards = RewardCategories(context: store.context)
        try rewards.setRewardsAs(of: try store.category("Food & Beverage"), to: "dining")
        try rewards.setRewardsAs(of: try store.category("Products"), to: "groceries")
        let (card, _) = try linked(Self.topSpend, statementDay: 5)
        let other = try store.context.addCard("Other", paidFrom: store.checking)
        func pay(_ cents: Int, _ category: String, on day: CalendarDay, with paying: Card) throws {
            try store.record(-cents, category, on: day).card = paying
        }
        try pay(40_00, "Restaurants", on: day(2026, 10, 7), with: card)
        try pay(10_00, "Café", on: day(2026, 10, 8), with: card)
        try pay(30_00, "Products", on: day(2026, 10, 8), with: card)
        try pay(99_00, "Products", on: day(2026, 10, 4), with: card)
        try pay(99_00, "Products", on: day(2026, 10, 8), with: other)
        try store.record(5_00, "Salary", .income, on: day(2026, 10, 8)).card = card
        try store.context.save()

        let spending = try CardTopSpend.spending(of: card, on: TestStore.today, in: store.context)
        #expect(spending == ["dining": 50_00, "groceries": 30_00])
    }

    // MARK: Shown, never earned

    @Test func paidWithAndMerchantRatesAreShownAndNeverEarned() throws {
        let catalog = try Fixture.catalog(cards: [Fixture.savory])
        var draft = CardDraft.new(from: try #require(catalog.cards.first))
        draft.payingWallet = store.checking
        let card = try Card.create(draft, in: store.context)
        let page = CardRewards(of: card, in: catalog).page(on: TestStore.today)
        #expect(page.conditional.map { $0.rule?.paysWith ?? $0.rule?.merchants.first } == ["Apple Pay", "Amazon"])
        #expect(earning(card, catalog, "online-shopping")?.effectiveRate == 1)
        #expect(earning(card, catalog, "travel")?.effectiveRate == 1)
    }

    @Test func rulesTheAppCanNeverTellAreNotEarnedThroughChoiceOrRotation() throws {
        let card = Fixture.card("test-excluded", "Excluded", issuer: "Test Bank", kind: "cashback", rules: [
            Fixture.rule(["everything-else"], 1),
            Fixture.rule(["gas", "dining"], 6, selection: "choose", firstMonths: 12, needs: ["account-opened"]),
            Fixture.rule(["gas", "dining"], 4, selection: "choose", requires: ["preferred-rewards-tier"], tier: "gold"),
            Fixture.rule(["groceries"], 5, selection: "rotating", paysWith: "PayPal", validFrom: "2026-10-01",
                         validTo: "2026-12-31"),
        ])
        let (linked, catalog) = try linked(card)
        let page = CardRewards(of: linked, in: catalog).page(on: TestStore.today)
        #expect(page.choices.isEmpty)
        #expect(page.quarters.isEmpty)
        #expect(page.conditional.map { $0.rule?.paysWith } == ["PayPal"])
        #expect(earning(linked, catalog, "groceries")?.effectiveRate == 1)
    }

    @Test func aQuartersMerchantsAreShownWithIt() throws {
        var quarter = Self.quarter(["groceries"], from: "2026-10-01", to: "2026-12-31")
        quarter["merchants"] = ["American Red Cross®"]
        let card = Fixture.card("test-q", "Q", issuer: "Test Bank", kind: "cashback", rules: [Fixture.rule(["everything-else"], 1), quarter])
        let (linked, catalog) = try linked(card)
        #expect(CardRewards(of: linked, in: catalog).page(on: TestStore.today).quarters.first?.merchants == ["American Red Cross®"])
    }

    @Test func aQuarterIsEarnedByThePurchasesOwnDay() throws {
        let (card, catalog) = try linked(Self.flex(stacks: false))
        #expect(earning(card, catalog, "groceries", on: day(2026, 9, 20))?.effectiveRate == 1)
        #expect(earning(card, catalog, "groceries", on: day(2026, 12, 31))?.effectiveRate == 5)
    }

    @Test func yourChoiceKeepsWhenANewerCatalogCorrectsTheRate() throws {
        let (card, catalog) = try linked(Self.customized)
        let key = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first?.key)
        try card.setYourChoice(["gas"], for: key, in: catalog)
        var corrected = Self.customized
        corrected["rules"] = [
            Fixture.rule(["everything-else"], 1), Fixture.rule(["gas", "online-shopping", "dining", "travel"], 3.5, selection: "choose"),
        ]
        let newer = try Fixture.catalog(cards: [corrected])
        #expect(earning(card, newer, "gas")?.effectiveRate == 3.5)
    }

    @Test func pickingAnOptionReplacesOrTogglesYourChoiceUpToItsPicks() throws {
        let (card, catalog) = try linked(Self.customized)
        let one = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first)
        let gas = try #require(one.options.first { $0.id == "gas" })
        let dining = try #require(one.options.first { $0.id == "dining" })
        #expect(one.choosing(gas) == ["gas"])
        var two = Fixture.rule(["gas", "dining", "travel"], 5, selection: "choose")
        two["picks"] = 2
        let (other, otherCatalog) = try linked(Fixture.card("test-two", "Two", issuer: "Test Bank", kind: "cashback", rules: [two]))
        let choice = try #require(CardRewards(of: other, in: otherCatalog).page(on: TestStore.today).choices.first)
        try other.setYourChoice(choice.choosing(gas), for: choice.key, in: otherCatalog)
        let afterGas = try #require(CardRewards(of: other, in: otherCatalog).page(on: TestStore.today).choices.first)
        #expect(afterGas.choosing(dining) == ["gas", "dining"])
        #expect(afterGas.choosing(gas) == [])
    }

    // MARK: Change catalog card

    @Test func changingCatalogCardRemovesYourChoice() throws {
        let catalog = try Fixture.catalog(cards: [Self.flex(), Self.customized])
        var draft = CardDraft.new(from: try #require(catalog.card("test-customized")))
        draft.payingWallet = store.checking
        let card = try Card.create(draft, in: store.context)
        let key = try #require(CardRewards(of: card, in: catalog).page(on: TestStore.today).choices.first?.key)
        try card.setYourChoice(["gas"], for: key, in: catalog)
        try card.link(to: try #require(catalog.card("test-flex")))
        #expect(card.yourChoices.isEmpty)
    }

    // MARK: The Card picker

    @Test func thePickerSaysWhatACategoryEarnsAddedUp() throws {
        let (card, catalog) = try linked(Self.flex())
        try RewardCategories(context: store.context).setRewardsAs(of: try store.category("Products"), to: "groceries")
        let order = CardEarning.ordered(
            [card], for: try store.category("Products"), in: catalog, own: [], on: TestStore.today, spending: { _ in [:] }
        )
        #expect(order.first?.detail == "5% · Groceries")
    }
}
