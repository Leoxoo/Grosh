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

    @Test func searchMatchesNameAndIssuerWhateverTheCase() throws {
        let catalog = try RewardsCatalogFixture.catalog()
        #expect(catalog.search("voyager").map(\.id) == ["test-voyager-points"])
        #expect(catalog.search("test bank").map(\.id) == ["test-old-miles", "test-savory-cash"])
        #expect(catalog.search("credit savory").isEmpty)
        #expect(catalog.search("  ").map(\.id) == ["test-voyager-points", "test-old-miles", "test-savory-cash"])
    }
}
