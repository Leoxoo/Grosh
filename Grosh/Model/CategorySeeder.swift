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

    private static func insert(_ seed: CategorySeed, parent: Category?, sortOrder: Int, into context: ModelContext) {
        let category = Category(
            name: seed.name,
            type: seed.type,
            symbolName: seed.symbolName,
            color: seed.color,
            lockedRole: seed.lockedRole,
            parent: parent,
            sortOrder: sortOrder
        )
        context.insert(category)
        for (order, child) in seed.children.enumerated() {
            insert(child, parent: category, sortOrder: order, into: context)
        }
    }
}
