import Foundation

/// The kind of purchase a card's rate is for, in the words banks use: one of the fixed list every user shares
/// (``fixed``), or one the user added (``OwnRewardCategory``). Each of the user's Expense categories counts as one
/// (``Category/rewardsAs``).
nonisolated struct RewardCategory: Hashable, Identifiable, Sendable {
    /// For the fixed list, the rewards catalog's own category word (`dining`, `ev-charging`), so a catalog rate's
    /// category is a Reward category's id. For the user's own, its ``OwnRewardCategory/key``.
    let id: String
    let name: String
    /// Whether the user added it. Only rates the user enters earn on their own Reward categories.
    let isOwn: Bool

    private init(_ id: String, _ name: LocalizedStringResource) {
        self.init(id: id, name: String(localized: name), isOwn: false)
    }

    init(id: String, name: String, isOwn: Bool) {
        self.id = id
        self.name = name
        self.isOwn = isOwn
    }

    init(_ own: OwnRewardCategory) {
        self.init(id: own.key, name: own.name, isOwn: true)
    }

    /// What every purchase no other rate covers counts as: a card's Base rate. Last in every list.
    static let everythingElse = RewardCategory("everything-else", Strings.Rewards.everythingElse)

    /// The Reward categories every user has, in the order they are listed, Everything else last. Their ids are the
    /// rewards catalog's categories (`CATEGORIES` in `tools/rewards-catalog/pipeline/extract.py`).
    static let fixed: [RewardCategory] = [
        RewardCategory("dining", Strings.Rewards.dining),
        RewardCategory("groceries", Strings.Rewards.groceries),
        RewardCategory("gas", Strings.Rewards.gas),
        RewardCategory("ev-charging", Strings.Rewards.evCharging),
        RewardCategory("travel", Strings.Rewards.travel),
        RewardCategory("airlines", Strings.Rewards.airlines),
        RewardCategory("hotels", Strings.Rewards.hotels),
        RewardCategory("transit", Strings.Rewards.transit),
        RewardCategory("streaming", Strings.Rewards.streaming),
        RewardCategory("entertainment", Strings.Rewards.entertainment),
        RewardCategory("drugstores", Strings.Rewards.drugstores),
        RewardCategory("online-shopping", Strings.Rewards.onlineShopping),
        RewardCategory("home-improvement", Strings.Rewards.homeImprovement),
        RewardCategory("fitness", Strings.Rewards.fitness),
        RewardCategory("phone-internet", Strings.Rewards.phoneInternet),
        RewardCategory("utilities", Strings.Rewards.utilities),
        RewardCategory("wholesale-clubs", Strings.Rewards.wholesaleClubs),
        RewardCategory("department-stores", Strings.Rewards.departmentStores),
        everythingElse,
    ]

    /// The fixed Reward category with `id`, or `nil` for an id the list doesn't have (the user's own, or a category a
    /// newer catalog added).
    static func fixed(_ id: String) -> RewardCategory? {
        fixedByID[id]
    }

    private static let fixedByID = Dictionary(uniqueKeysWithValues: fixed.map { ($0.id, $0) })

    /// The Reward category `id` names among `listed`, or Everything else for none, or for one that no longer exists:
    /// what a category counting as it earns as.
    static func named(_ id: String?, in listed: [RewardCategory]) -> RewardCategory {
        listed.first { $0.id == id } ?? everythingElse
    }

    /// The Reward category a picker of Rewards as shows chosen for a category whose own is `own`: that, or for a
    /// top-level one with none, Everything else, or for a subcategory with none, `nil`, its "Same as parent" choice.
    static func shownChoice(own: String?, isSubcategory: Bool) -> String? {
        own ?? (isSubcategory ? nil : everythingElse.id)
    }

    /// The fixed list with the user's `own` Reward categories before Everything else, as every list of them reads.
    static func listed(own: [RewardCategory]) -> [RewardCategory] {
        fixed.dropLast() + own + [everythingElse]
    }
}

extension Category {
    /// Whether the user sets this category's Rewards as: an Expense category of their own. Income, Debt/Loan and the
    /// app's own categories have none to set.
    var offersRewardsAs: Bool { type == .expense && !isLocked }

    /// The id of the Reward category a purchase in this category counts as: its own, else its parent's, else Everything
    /// else. `nil` for a category that isn't an Expense, or is one half of a Transfer, which no card earns on. Reads
    /// only this category and its parent, so a list or a picker can ask it of every transaction.
    var rewardsAs: String? {
        guard type == .expense, !isTransferHalf else { return nil }
        return (offersRewardsAs ? ownRewardsAs : nil) ?? parent?.rewardsAs ?? RewardCategory.everythingElse.id
    }
}
