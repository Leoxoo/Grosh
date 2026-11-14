import Foundation
import SwiftData

/// Why ``RewardCategories`` refused a change.
nonisolated enum RewardCategoryError: RuleRefusal, Equatable {
    case nameRequired
    /// Reward category names are unique, the fixed list's included, ignoring case.
    case nameTaken
}

extension RewardCategoryError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .nameRequired: String(localized: Strings.Rewards.nameRequired)
        case .nameTaken: String(localized: Strings.Rewards.nameTaken)
        }
    }
}

/// The Reward categories, fixed and the user's own, and which of the user's categories count as each: the rules
/// behind Account → Cards → Reward categories.
struct RewardCategories {
    let context: ModelContext

    /// One Reward category and the user's categories that count as it, in tree order.
    struct Entry: Identifiable {
        let reward: RewardCategory
        let categories: [Category]
        var id: String { reward.id }
    }

    /// The user's own Reward categories in the order they were added.
    static var ownInOrder: FetchDescriptor<OwnRewardCategory> {
        FetchDescriptor(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
    }

    /// Every Reward category in list order: the fixed list with the user's own before Everything else.
    func all() throws -> [RewardCategory] {
        RewardCategory.listed(own: try context.fetch(Self.ownInOrder).map(RewardCategory.init))
    }

    /// Every Reward category with the user's categories counting as it, read from the store (``map(of:own:)``).
    func map() throws -> [Entry] {
        Self.map(
            of: try context.fetch(FetchDescriptor<Category>()), own: try context.fetch(Self.ownInOrder).map(RewardCategory.init)
        )
    }

    /// Every Reward category in list order, with the categories found in `all` counting as it: the Expense categories
    /// whose Rewards as the user sets, in tree order, hidden ones included. A category counting as a Reward category
    /// that no longer exists is listed under Everything else, which is what it earns as. For a screen that already
    /// holds the categories and the user's `own` Reward categories from a query.
    static func map(of all: [Category], own: [RewardCategory]) -> [Entry] {
        let rewards = RewardCategory.listed(own: own)
        let known = Set(rewards.map(\.id))
        let categories = CategoryCatalog.tree(of: .expense, from: all).filter(\.offersRewardsAs)
        let byReward = Dictionary(grouping: categories) { category in
            category.rewardsAs.flatMap { known.contains($0) ? $0 : nil } ?? RewardCategory.everythingElse.id
        }
        return rewards.map { Entry(reward: $0, categories: byReward[$0.id] ?? []) }
    }

    /// Sets the Reward category `category` counts as, or with `nil` lets it follow its parent's (a top-level one's is
    /// then Everything else), as its editor would. Saves.
    func setRewardsAs(of category: Category, to id: String?) throws {
        var draft = CategoryDraft(category)
        draft.ownRewardsAs = id
        try CategoryCatalog(context: context).update(category, to: draft)
    }

    /// Adds a Reward category of the user's own, after the others they added. Saves.
    @discardableResult
    func add(named name: String) throws -> OwnRewardCategory {
        let name = try checkedName(name, except: nil)
        let own = OwnRewardCategory(name: name, sortOrder: try context.nextSortOrder(\OwnRewardCategory.sortOrder))
        context.insert(own)
        try context.save()
        return own
    }

    /// Renames one of the user's own Reward categories. Saves.
    func rename(_ own: OwnRewardCategory, to name: String) throws {
        own.name = try checkedName(name, except: own)
        try own.saveToStore()
    }

    /// Removes one of the user's own Reward categories. Every category that counted as it goes back to Everything else:
    /// a top-level one to having none of its own, a subcategory to Everything else of its own, so it doesn't take up
    /// its parent's instead, and every rate a Card had for it goes too. Saves.
    func delete(_ own: OwnRewardCategory) throws {
        let id: String? = own.key
        let counting = try context.fetch(FetchDescriptor<Category>(predicate: #Predicate { $0.ownRewardsAs == id }))
        for category in counting {
            category.ownRewardsAs = category.parent == nil ? nil : RewardCategory.everythingElse.id
        }
        let rated = try context.fetch(FetchDescriptor<Card>(predicate: #Predicate { $0.enteredRatesData != nil }))
        for card in rated where card.enteredRates.contains(where: { $0.reward == own.key }) {
            try card.keepEnteredRates(card.enteredRates.filter { $0.reward != own.key })
        }
        try own.storeContext().delete(own)
        try context.save()
    }

    private func checkedName(_ name: String, except own: OwnRewardCategory?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RewardCategoryError.nameRequired }
        let taken = try all().contains {
            $0.id != own?.key && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        guard !taken else { throw RewardCategoryError.nameTaken }
        return trimmed
    }
}
