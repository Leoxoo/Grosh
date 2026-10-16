import Foundation
import SwiftData

extension CategoryCatalog {
    // MARK: Choosing

    /// How many days back, today included, a category's transactions count toward how much it is used lately.
    static let recentUseDays = 30

    /// `categories`, given in tree order, as a category list offers them: the parents used most lately first, each
    /// followed by its subcategories in their usual order, so a subcategory is always found in the same place within
    /// its parent. A parent goes by its own transactions and its subcategories' together. Used lately means dated in
    /// the last ``recentUseDays`` days through `today`; transactions in Recently Deleted or dated after today don't
    /// count. Parents used as often keep their tree order, so unused ones stay put.
    static func byRecentUse(
        _ categories: [Category], transactions: [Transaction], today: CalendarDay
    ) -> [Category] {
        let days: ClosedRange<Int> = today.adding(days: -(recentUseDays - 1)).rawValue...today.rawValue
        var counts: [PersistentIdentifier: Int] = [:]
        for transaction in transactions where transaction.deletedAt == nil && days.contains(transaction.dayRaw) {
            if let category = transaction.category {
                counts[category.persistentModelID, default: 0] += 1
            }
        }

        // Each subcategory joins its parent's group when the parent is offered too; otherwise it leads its own.
        var groups: [ParentGroup] = []
        var groupOf: [PersistentIdentifier: Int] = [:]
        for category in categories {
            if let parent = category.parent, let group = groupOf[parent.persistentModelID] {
                groups[group].subcategories.append(category)
            } else {
                groupOf[category.persistentModelID] = groups.count
                groups.append(ParentGroup(parent: category))
            }
        }

        let uses: [Int] = groups.map { group in
            group.members.reduce(0) { total, category in total + (counts[category.persistentModelID] ?? 0) }
        }
        let order: [Int] = groups.indices.sorted { lhs, rhs in
            uses[lhs] == uses[rhs] ? lhs < rhs : uses[lhs] > uses[rhs]
        }
        return order.flatMap { groups[$0].members }
    }

    /// The categories whose names contain `query`, whatever the case or accents, in the order given. An empty or blank
    /// query keeps them all.
    static func matching(_ query: String, in categories: [Category]) -> [Category] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.filter { $0.name.localizedStandardContains(query) }
    }

    /// A parent and the subcategories offered with it, which a category list keeps together.
    private struct ParentGroup {
        let parent: Category
        var subcategories: [Category] = []

        /// The parent, then its subcategories in tree order.
        var members: [Category] { [parent] + subcategories }
    }
}
