import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A store saved before a category could count as several Reward categories opens with each category's one Rewards
/// as kept, now as the only one in its list (ADR-0015).
@MainActor
@Suite(.namedInTheLog)
struct RewardsAsUpgradeTests {
    /// The categories as a store kept them before: one Reward category each, in `ownRewardsAs`.
    enum StoreBeforeSeveral: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)
        static var models: [any PersistentModel.Type] { [Category.self] }

        @Model
        final class Category {
            var name: String = ""
            @Attribute(originalName: "typeValue") var typeRaw: String = "expense"
            @Attribute(originalName: "iconName") var symbolName: String = "questionmark"
            var colorName: String = "gray"
            var isHidden: Bool = false
            @Attribute(originalName: "roleValue") var lockedRoleRaw: String?
            var sortOrder: Int = 0
            var ownKindRaw: String?
            var ownRewardsAs: String?
            var parent: Category?
            @Relationship(deleteRule: .nullify, inverse: \Category.parent)
            var children: [Category]? = []

            init(name: String, ownRewardsAs: String?, parent: Category? = nil) {
                self.name = name
                self.ownRewardsAs = ownRewardsAs
                self.parent = parent
            }
        }
    }

    @Test func aStoreFromBeforeOpensWithEachCategorysRewardsAsKept() throws {
        let url = URL.temporaryDirectory
            .appending(path: "GroshTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            .appending(path: "Grosh.store")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let before = try ModelContainer(
                for: Schema(versionedSchema: StoreBeforeSeveral.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none)
            )
            let trips = StoreBeforeSeveral.Category(name: "Trips", ownRewardsAs: "travel")
            before.mainContext.insert(trips)
            before.mainContext.insert(StoreBeforeSeveral.Category(name: "Flights", ownRewardsAs: "airlines", parent: trips))
            before.mainContext.insert(StoreBeforeSeveral.Category(name: "Souvenirs", ownRewardsAs: nil, parent: trips))
            try before.mainContext.save()
        }

        let container = try GroshStore.makeContainer(at: url)
        try StoreOpening.prepare(container.mainContext)
        let categories = try container.mainContext.fetch(FetchDescriptor<Grosh.Category>())
        func named(_ name: String) throws -> Grosh.Category { try #require(categories.first { $0.name == name }) }

        #expect(try named("Trips").ownRewardsAs == ["travel"])
        #expect(try named("Flights").ownRewardsAs == ["airlines"])
        #expect(try named("Souvenirs").ownRewardsAs.isEmpty)
        #expect(try named("Souvenirs").rewardsAs == ["travel"])
        #expect(categories.allSatisfy { $0.singleRewardsAs == nil })
    }
}
