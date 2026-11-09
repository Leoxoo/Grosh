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

    /// Puts back what an upgrade from an older build can lose. Older builds stored a category's type, icon and locked
    /// role under other names, and an upgrade that didn't carry them over left every category an Expense with a
    /// question-mark icon and no locked role, so wallets and imports couldn't find their Starting balance or Other
    /// Income. A healthy store always has Income and Debt/Loan categories, so only a store with none of them gets its
    /// types back, by name from the seeded tree. A locked category keeps its seeded name, and an icon is only replaced
    /// while it is still the placeholder. Runs on every launch and changes nothing once the store is complete. Saves
    /// when it changed something.
    static func restoreMissingDefaults(in context: ModelContext) throws {
        var categories = try context.fetch(FetchDescriptor<Category>())
        let seeds = allSeeds(in: DefaultCategories.tree)
        var changed = false
        if !categories.isEmpty, categories.allSatisfy({ $0.type == .expense }) {
            for category in categories {
                if let seed = seeds.first(where: { $0.name == category.name }), seed.type != category.type {
                    category.type = seed.type
                    changed = true
                }
            }
        }
        for seed in seeds {
            let matches = categories.filter { $0.name == seed.name && $0.type == seed.type }
            for category in matches where category.symbolName == "questionmark" {
                category.symbolName = seed.symbolName
                changed = true
            }
            guard let role = seed.lockedRole, !categories.contains(where: { $0.lockedRole == role }) else { continue }
            if let match = matches.first {
                match.lockedRole = role
            } else {
                let sortOrder = (categories.map(\.sortOrder).max() ?? -1) + 1
                insert(seed, parent: nil, sortOrder: sortOrder, into: context)
                categories = try context.fetch(FetchDescriptor<Category>())
            }
            changed = true
        }
        if changed {
            try context.save()
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
