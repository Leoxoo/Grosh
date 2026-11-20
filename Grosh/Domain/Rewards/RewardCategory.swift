import Foundation

/// The kind of purchase a card's rate is for, in the words banks use: one of the fixed list every user shares
/// (``fixed``), or one the user added (``OwnRewardCategory``). Each of the user's Expense categories counts as one or
/// more (``Category/rewardsAs``, ADR-0015).
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
    /// rewards catalog's categories (`CATEGORY_TABLE` in `tools/rewards-catalog/pipeline/extract.py`; its test reads this list, so the two can't drift).
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

    /// The names of the Reward categories `ids` names among `listed`, as one phrase ("Travel and Airlines"); ids that no
    /// longer exist read as Everything else, once.
    static func names(of ids: [String], in listed: [RewardCategory]) -> String {
        var names: [String] = []
        for id in ids {
            let name = named(id, in: listed).name
            if !names.contains(name) { names.append(name) }
        }
        return names.formatted(.list(type: .and))
    }

    /// The Reward categories a menu of Rewards as checks for a category whose own are `own`: those, or for a top-level
    /// one with none, Everything else, or for a subcategory with none, none: its "Same as parent" choice is checked.
    static func shownChoices(own: [String], isSubcategory: Bool) -> [String] {
        own.isEmpty && !isSubcategory ? [everythingElse.id] : own
    }

    /// `chosen` after the menu's checkmark on `id` is tapped: `id` added, or taken out when it was there, in `listed`
    /// order. Everything else never sits beside another: checking it clears the others, and checking another clears
    /// it (ADR-0015). Taking out the last leaves none, so the category follows its parent, or is Everything else.
    static func toggled(_ id: String, in chosen: [String], listed: [RewardCategory]) -> [String] {
        if chosen.contains(id) { return chosen.filter { $0 != id } }
        if id == everythingElse.id { return [id] }
        let added = Set(chosen + [id]).subtracting([everythingElse.id])
        let order = Dictionary(listed.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return added.sorted { (order[$0] ?? .max, $0) < (order[$1] ?? .max, $1) }
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

    /// The ids of the Reward categories a purchase in this category counts as, never empty: its own, else its
    /// parent's, else Everything else. A purchase earns the best rate among them (ADR-0015). `nil` for a category that
    /// isn't an Expense, or is one half of a Transfer, which no card earns on. Reads only this category and its parent,
    /// so a list or a picker can ask it of every transaction.
    var rewardsAs: [String]? {
        guard type == .expense, !isTransferHalf else { return nil }
        let own = offersRewardsAs ? ownRewardsAs : []
        return own.isEmpty ? parent?.rewardsAs ?? [RewardCategory.everythingElse.id] : own
    }
}
