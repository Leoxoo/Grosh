import Foundation

/// Which Reward categories Best Card shows as tiles, and in what order: the user's Customize.
nonisolated struct BestCardLayout: Codable, Equatable, Sendable {
    /// Every Reward category as the user last arranged them, shown or not, by id.
    var order: [String]
    /// The ones whose tile is not shown, by id.
    var hidden: [String]

    /// The Reward categories shown before the user customizes, the ones most purchases count as, in this order.
    static let starter = ["dining", "groceries", "gas", "travel", "online-shopping", "streaming", "drugstores", "transit"]

    /// The layout before the user customizes: the starter tiles, then the user's own Reward categories, then
    /// Everything else; the rest are hidden, in list order after them.
    static func starting(_ listed: [RewardCategory]) -> BestCardLayout {
        let ids = listed.map(\.id)
        let shown = starter.filter(ids.contains) + listed.filter(\.isOwn).map(\.id) + [RewardCategory.everythingElse.id]
        let rest = ids.filter { !shown.contains($0) }
        return BestCardLayout(order: shown + rest, hidden: rest)
    }

    /// The layout kept as `stored` (``stored``), or the starting one when nothing is kept or it can't be read.
    static func read(_ stored: String, listed: [RewardCategory]) -> BestCardLayout {
        guard let data = stored.data(using: .utf8), let layout = try? JSONDecoder().decode(Self.self, from: data) else {
            return starting(listed)
        }
        return layout
    }

    /// The layout as the app keeps it in `UserDefaults`, as JSON.
    var stored: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// Every Reward category in `listed` in the user's order, each with whether its tile is shown. Ones added since the
    /// user arranged them come last, shown; ones that no longer exist are left out.
    func arranged(_ listed: [RewardCategory]) -> [(reward: RewardCategory, isShown: Bool)] {
        let byID = Dictionary(listed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let known = Set(order)
        let rewards = order.compactMap { byID[$0] } + listed.filter { !known.contains($0.id) }
        let hidden = Set(hidden)
        return rewards.map { ($0, !hidden.contains($0.id)) }
    }

    /// The Reward categories whose tiles Best Card shows, in the user's order.
    func shown(_ listed: [RewardCategory]) -> [RewardCategory] {
        arranged(listed).filter(\.isShown).map(\.reward)
    }

    /// The layout once the tile of `id` is shown when it was hidden, or hidden when it was shown.
    func toggled(_ id: String, in listed: [RewardCategory]) -> BestCardLayout {
        var layout = normalized(listed)
        if layout.hidden.contains(id) { layout.hidden.removeAll { $0 == id } } else { layout.hidden.append(id) }
        return layout
    }

    /// The layout once the Reward categories at `source` in ``arranged(_:)`` are moved to before `destination`, as a
    /// list's drag reports it.
    func moved(from source: IndexSet, to destination: Int, in listed: [RewardCategory]) -> BestCardLayout {
        var layout = normalized(listed)
        let moving = source.map { layout.order[$0] }
        var kept = layout.order.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        kept.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
        layout.order = kept
        return layout
    }

    /// The layout naming exactly the Reward categories in `listed`, in ``arranged(_:)`` order.
    private func normalized(_ listed: [RewardCategory]) -> BestCardLayout {
        let arranged = arranged(listed)
        return BestCardLayout(order: arranged.map(\.reward.id), hidden: arranged.filter { !$0.isShown }.map(\.reward.id))
    }
}

/// Best Card's search: the Reward categories a search finds, shown or not.
nonisolated enum BestCardSearch {
    /// The Reward categories among `rewards`, in their order, whose name or the name of one of the user's categories
    /// counting as it (`categoryNames`, by Reward category id) contains `text`, ignoring case and accents. Every one for
    /// blank text.
    static func matches(_ text: String, in rewards: [RewardCategory], categoryNames: [String: [String]]) -> [RewardCategory] {
        let text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return rewards }
        func has(_ name: String) -> Bool { name.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        return rewards.filter { has($0.name) || (categoryNames[$0.id] ?? []).contains(where: has) }
    }
}
