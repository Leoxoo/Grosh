import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Card picker of an Expense, once its category is picked: the wallet's Cards best first for what that category
/// earns, Cards without a rate for it after in the user's order, and a second line saying what each earns.
@MainActor
@Suite(.namedInTheLog)
struct CardPickerOrderTests {
    private let store: TestStore
    private let catalog: RewardsCatalog

    init() throws {
        store = try TestStore()
        catalog = try RewardsCatalogFixture.catalog()
        try RewardCategories(context: store.context).setRewardsAs(of: try store.category("Food & Beverage"), to: "dining")
    }

    private func linked(_ name: String, to id: String, pointValue: Double = 1) throws -> Card {
        var draft = CardDraft.new(from: try #require(catalog.card(id)))
        draft.name = name
        draft.payingWallet = store.checking
        draft.pointValueCents = pointValue
        return try Card.create(draft, in: store.context)
    }

    private func ordered(_ cards: [Card], for category: Grosh.Category?) -> [CardEarning] {
        CardEarning.ordered(cards, for: category, in: catalog, own: [], on: TestStore.today, spending: { _ in [:] })
    }

    @Test func cardsAreOrderedByWhatTheCategoryEarnsWithUnratedCardsAfterInTheirOrder() throws {
        let plain = try store.context.addCard("Debit", kind: .debit, paidFrom: store.checking)
        let savory = try linked("Savory", to: "test-savory-cash")
        let miles = try linked("Miles", to: "test-old-miles")
        let voyager = try linked("Voyager", to: "test-voyager-points", pointValue: 1.5)
        let custom = try store.context.addCard("Local", paidFrom: store.checking)
        try custom.saveRate(in: catalog, EnteredRate(reward: "dining", rate: 3), replacing: nil)

        let order = ordered([plain, savory, miles, voyager, custom], for: try store.category("Restaurants"))
        #expect(order.map(\.card.name) == ["Voyager", "Savory", "Local", "Miles", "Debit"])
        #expect(order.map { $0.earning?.effectiveRate } == [4.5, 3, 3, 2, nil])
        #expect(order.map { $0.earning?.reward.id } == ["dining", "dining", "dining", "everything-else", nil])
    }

    @Test func noCategoryLeavesTheCardsAsTheyAre() throws {
        let plain = try store.context.addCard("Debit", kind: .debit, paidFrom: store.checking)
        let savory = try linked("Savory", to: "test-savory-cash")
        let order = ordered([plain, savory], for: nil)
        #expect(order.map(\.card) == [plain, savory])
        #expect(order.allSatisfy { $0.earning == nil })
        let income = ordered([plain, savory], for: try store.category("Salary", .income))
        #expect(income.map(\.card) == [plain, savory])
        #expect(income.allSatisfy { $0.earning == nil })
    }

    @Test func theSecondLineSaysWhatTheCardEarns() throws {
        let savory = try linked("Savory", to: "test-savory-cash")
        let voyager = try linked("Voyager", to: "test-voyager-points")
        let order = ordered([savory, voyager], for: try store.category("Café"))
        #expect(order.map(\.detail) == ["3% · Dining", "3× · 3% · Dining"])
        #expect(ordered([savory], for: try store.category("Education")).first?.detail == "1% · Everything else")
    }

    @Test func pickingACategoryNeverPicksACard() throws {
        _ = try linked("Savory", to: "test-savory-cash")
        var draft = TransactionDraft(type: .expense, day: TestStore.today)
        draft.wallet = store.checking
        draft.category = try store.category("Restaurants")
        #expect(draft.card == nil)
    }
}
