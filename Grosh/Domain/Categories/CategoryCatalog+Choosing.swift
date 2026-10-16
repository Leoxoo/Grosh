import Foundation
import SwiftData

extension CategoryCatalog {
    // MARK: Choosing

    /// How many days back, today included, a category's transactions count toward how much it is used lately.
    static let recentUseDays = 30

    /// `categories`, given in tree order, as a category list offers them: the most used lately first. A parent goes
    /// by its own transactions and its subcategories' together, and its subcategories follow it, the most used first.
    /// Used lately means dated in the last ``recentUseDays`` days through `today`; transactions in Recently Deleted
    /// or dated after today don't count. Categories used as often keep their tree order, so unused ones stay put.
    static func byRecentUse(
        _ categories: [Category], transactions: [Transaction], today: CalendarDay
    ) -> [Category] {
        let days = today.adding(days: -(recentUseDays - 1)).rawValue...today.rawValue
        var counts: [PersistentIdentifier: Int] = [:]
        for transaction in transactions where transaction.deletedAt == nil && days.contains(transaction.dayRaw) {
            if let category = transaction.category {
                counts[category.persistentModelID, default: 0] += 1
            }
        }
        func uses(of category: Category) -> Int { counts[category.persistentModelID] ?? 0 }

        // Each subcategory joins its parent's group when the parent is offered too; otherwise it leads its own.
        var groups: [(parent: Category, subcategories: [Category])] = []
        var groupOf: [PersistentIdentifier: Int] = [:]
        for category in categories {
            if let parent = category.parent, let group = groupOf[parent.persistentModelID] {
                groups[group].subcategories.append(category)
            } else {
                groupOf[category.persistentModelID] = groups.count
                groups.append((category, []))
            }
        }

        return mostUsedFirst(groups) { group in
            uses(of: group.parent) + group.subcategories.reduce(0) { $0 + uses(of: $1) }
        }
        .flatMap { [$0.parent] + mostUsedFirst($0.subcategories, uses: uses(of:)) }
    }

    /// The categories whose names contain `query`, whatever the case or accents, in the order given. An empty or blank
    /// query keeps them all.
    static func matching(_ query: String, in categories: [Category]) -> [Category] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        return categories.filter { $0.name.localizedStandardContains(query) }
    }

    /// `elements` with the most used first; those used as often keep the order they had.
    private static func mostUsedFirst<Element>(_ elements: [Element], uses: (Element) -> Int) -> [Element] {
        elements.enumerated()
            .map { (offset: $0.offset, element: $0.element, uses: uses($0.element)) }
            .sorted { $0.uses == $1.uses ? $0.offset < $1.offset : $0.uses > $1.uses }
            .map { $0.element }
    }
}
