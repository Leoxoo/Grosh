import Foundation
import SwiftData

/// Seeds the category tree on first launch from `CategorySeed.json`. The tree is data, not code,
/// so it can be swapped for a generic starter set without touching the app's logic.
enum CategorySeed {
    /// Inserts the bundled tree unless the store already has categories.
    static func seedIfNeeded(_ context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Category>()) == 0 else { return }
        guard let url = Bundle.main.url(forResource: "CategorySeed", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let groups = try JSONDecoder().decode([Group].self, from: Data(contentsOf: url))
        for group in groups {
            insert(group.categories, type: group.type, parent: nil, into: context)
        }
        try context.save()
    }

    /// Inserts sibling categories in the order given, then each one's subcategories.
    private static func insert(_ nodes: [Node], type: CategoryType, parent: Category?, into context: ModelContext) {
        for (index, node) in nodes.enumerated() {
            let category = Category(
                name: node.name,
                type: type,
                iconName: node.icon,
                colorName: node.color ?? parent?.colorName ?? "gray",
                role: node.role,
                sortOrder: index
            )
            context.insert(category)
            category.parent = parent
            insert(node.children ?? [], type: type, parent: category, into: context)
        }
    }

    private nonisolated struct Group: Decodable {
        let type: CategoryType
        let categories: [Node]
    }

    private nonisolated struct Node: Decodable {
        let name: String
        let icon: String
        /// Subcategories without their own color take their parent's.
        let color: String?
        let role: CategoryRole?
        let children: [Node]?
    }
}
