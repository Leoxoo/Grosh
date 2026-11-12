import Foundation
import SwiftData

/// Fills an empty store with ``DefaultCategories``. Does nothing once any category exists, so a user's edits survive.
enum CategorySeeder {
    static func seedIfNeeded(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Category>()) == 0 else { return }
        for (order, seed) in DefaultCategories.tree.enumerated() {
            insert(seed, parent: nil, sortOrder: order, into: context)
        }
        try context.save()
    }

    /// Gives the store every locked category the app depends on, and repairs a store an older build's upgrade broke.
    /// Run at every open, after ``seedIfNeeded(in:)``; on a complete store it reads the locked categories and changes
    /// nothing. Saves when it changed something.
    static func restoreMissingDefaults(in context: ModelContext) throws {
        try repairLostUpgrade(in: context)
        try addMissingLockedCategories(in: context)
        if context.hasChanges {
            try context.save()
        }
    }

    /// The one-time repair of a store upgraded by a build that dropped three of a category's fields. Older builds kept
    /// a category's type, icon and locked role under other names (``Category`` now reads them through
    /// `originalName`), and that upgrade left every category an Expense with the placeholder icon and no locked role,
    /// so wallets and imports couldn't find their Starting balance or Other Income. Only a store with no locked role
    /// at all is one of those: the repair gives the roles back (``addMissingLockedCategories(in:)``), so it never runs
    /// on that store again. Types come back by name from the seeded tree while every category is an Expense, and an
    /// icon only while it is still the placeholder, so a choice the user made since is kept.
    private static func repairLostUpgrade(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Category>(predicate: #Predicate { $0.lockedRoleRaw != nil })) == 0
        else { return }
        let categories = try context.fetch(FetchDescriptor<Category>())
        let seeds = allSeeds(in: DefaultCategories.tree)
        if !categories.isEmpty, categories.allSatisfy({ $0.type == .expense }) {
            for category in categories {
                if let seed = seeds.first(where: { $0.name == category.name }), seed.type != category.type {
                    category.type = seed.type
                }
            }
        }
        for seed in seeds {
            for category in categories
            where category.name == seed.name && category.type == seed.type
                && category.symbolName == Category.placeholderSymbolName {
                category.symbolName = seed.symbolName
            }
        }
    }

    /// Gives each locked role a category: one the store lacks, as a store from before that role existed does, goes to
    /// the category of the role's seeded name and type, or else to a new one as seeded.
    private static func addMissingLockedCategories(in context: ModelContext) throws {
        let locked = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.lockedRoleRaw != nil }))
        let missing = Set(LockedRole.allCases).subtracting(locked.compactMap(\.lockedRole))
        guard !missing.isEmpty else { return }
        var categories = try context.fetch(FetchDescriptor<Category>())
        for seed in allSeeds(in: DefaultCategories.tree) {
            guard let role = seed.lockedRole, missing.contains(role) else { continue }
            if let match = categories.first(where: { $0.name == seed.name && $0.type == seed.type }) {
                match.lockedRole = role
            } else {
                let sortOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
                insert(seed, parent: nil, sortOrder: sortOrder, into: context)
                categories = try context.fetch(FetchDescriptor<Category>())
            }
        }
    }

    private static func allSeeds(in tree: [CategorySeed]) -> [CategorySeed] {
        tree.flatMap { [$0] + allSeeds(in: $0.children) }
    }

    private static func insert(_ seed: CategorySeed, parent: Category?, sortOrder: Int, into context: ModelContext) {
        // A top-level category starts as Regular; a subcategory has no Kind of its own, so it follows its parent.
        let category = Category(
            name: seed.name,
            type: seed.type,
            symbolName: seed.symbolName,
            color: seed.color,
            lockedRole: seed.lockedRole,
            parent: parent,
            sortOrder: sortOrder,
            ownKind: parent == nil ? RecurringKind.regular : nil
        )
        context.insert(category)
        for (order, child) in seed.children.enumerated() {
            insert(child, parent: category, sortOrder: order, into: context)
        }
    }
}
