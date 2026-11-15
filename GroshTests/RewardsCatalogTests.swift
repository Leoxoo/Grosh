import Foundation
import Testing
@testable import Grosh

/// Reading the rewards catalog the app ships (`rewards-catalog.json`, as the rewards pipeline publishes it) and
/// searching it, as Add Card does.
@Suite(.namedInTheLog)
struct RewardsCatalogTests {
    @Test func readsTheCatalogAsThePipelinePublishesIt() throws {
        let catalog = try RewardsCatalogFixture.catalog()
        #expect(catalog.cards.map(\.id) == ["test-savory-cash", "test-voyager-points", "test-old-miles"])
        let savory = try #require(catalog.card("test-savory-cash"))
        #expect(savory.name == "Savory Cash")
        #expect(savory.issuer == "Test Bank")
        #expect(savory.network == "Mastercard")
        #expect(savory.rewardKind == .cashback)
        let dining = try #require(savory.rules.first)
        #expect(dining.categories == ["dining", "groceries"])
        #expect(dining.rate == 3)
        #expect(dining.capAmount == 2500)
        #expect(dining.capPeriod == "quarter")
        #expect(dining.evidence.quote == "Earn 3% cash back on dining and at grocery stores.")
        #expect(dining.evidence.url == "https://bank.test/card")
        #expect(try #require(catalog.card("test-voyager-points")).annualFee == 95)
        #expect(catalog.card("not-in-the-catalog") == nil)
    }

    @Test func aFieldTheAppDoesntKnowIsIgnored() throws {
        let catalog = try RewardsCatalog(data: RewardsCatalogFixture.data(extra: ["generatedBy": "a newer pipeline"]))
        #expect(catalog.cards.count == 3)
    }

    @Test func aCatalogOfANewerFormatIsRefused() throws {
        #expect(throws: RewardsCatalogError.unknownFormat(2)) {
            try RewardsCatalog(data: RewardsCatalogFixture.data(formatVersion: 2))
        }
    }

    @Test func theCatalogShipsInTheAppAndIsReadWithoutANetwork() throws {
        let catalog = try RewardsCatalog.bundled()
        #expect(catalog.formatVersion == RewardsCatalog.formatVersion)
    }

    @Test func aRuleThePipelineLeftEmptyFieldsOutOfReadsThemAsNothing() throws {
        let data = Data(#"{"categories":["dining"],"selection":"fixed","rate":3,"unit":"percent","evidence":{"quote":"Q.","url":"https://bank.test"}}"#.utf8)
        let rule = try JSONDecoder().decode(CatalogRule.self, from: data)
        #expect(rule.categories == ["dining"])
        #expect(rule.rate == 3)
        #expect(rule.evidence.quote == "Q.")
        #expect(rule.picks == nil && rule.capAmount == nil && rule.capPeriod == nil && rule.paysWith == nil)
        #expect(rule.validFrom == nil && rule.validTo == nil && rule.firstMonths == nil && rule.tier == nil)
        #expect(!rule.hasOtherChoices && !rule.capUnknown)
        #expect(rule.requires.isEmpty && rule.needs.isEmpty && rule.conditions.isEmpty && rule.merchants.isEmpty)
    }

    @Test func aRuleWithoutItsRateIsRefused() {
        let data = Data(#"{"categories":["dining"],"selection":"fixed","unit":"percent","evidence":{"quote":"Q.","url":"u"}}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(CatalogRule.self, from: data) }
    }

    /// The pipeline and the app each keep their own list of categories, selections and units: this is what ties the
    /// shipped file to the app's (the pipeline's side is pinned by `tests/test_extract.py`).
    @Test func everyRuleInTheShippedCatalogUsesACategorySelectionAndUnitTheAppKnows() throws {
        let catalog = try RewardsCatalog.bundled()
        // Person-added categories come from tools/rewards-catalog/data/extra-categories.json.
        // Add each one there when it is added.
        let personAdded: Set<String> = ["car-rentals"]
        let categories = Set(RewardCategory.fixed.map(\.id)).union(personAdded)
        for card in catalog.cards {
            for rule in card.rules {
                #expect(Set(rule.categories).isSubset(of: categories), "\(card.id): \(rule.categories)")
                #expect(["fixed", "choose", "top-spend", "rotating"].contains(rule.selection), "\(card.id): \(rule.selection)")
                #expect(["percent", "per-dollar"].contains(rule.unit), "\(card.id): \(rule.unit)")
            }
        }
    }

    @Test func searchMatchesNameAndIssuerWhateverTheCase() throws {
        let catalog = try RewardsCatalogFixture.catalog()
        #expect(catalog.search("voyager").map(\.id) == ["test-voyager-points"])
        #expect(catalog.search("test bank").map(\.id) == ["test-old-miles", "test-savory-cash"])
        #expect(catalog.search("credit savory").isEmpty)
        #expect(catalog.search("  ").map(\.id) == ["test-voyager-points", "test-old-miles", "test-savory-cash"])
    }
}
