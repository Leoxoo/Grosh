import Foundation
import SwiftData

/// One rate a Card earns on a Reward category, as its page lists it.
nonisolated struct CardRate: Identifiable, Hashable, Sendable {
    let reward: RewardCategory
    /// Points or miles per dollar, for a points or miles Card; `nil` for cash back, whose rate is already an Effective
    /// rate.
    let multiplier: Double?
    /// What the Card earns as a share of what was spent, in percent: a cash back rate as it is, a points or miles rate
    /// times the Card's Point value. Rates are compared and sorted by it.
    let effectiveRate: Double
    /// The catalog's rule it comes from, with its cap, requirements, dates, conditions and quote.
    let rule: CatalogRule

    var id: String { reward.id }
}

/// What a Card earns: the catalog entry it is linked to, from the catalog the app ships, or from the rates the entry
/// last had when a newer catalog no longer has it (ADR-0014).
nonisolated struct CardRewards {
    /// The catalog entry, or `nil` for a Card that isn't linked.
    let entry: CatalogCard?
    /// Whether the Card is linked to an entry the catalog no longer has, so ``entry`` is the one it last saw, marked "No
    /// longer in the catalog".
    let isNoLongerInCatalog: Bool
    let pointValueCents: Double

    @MainActor
    init(of card: Card, in catalog: RewardsCatalog) {
        if let id = card.catalogCardID, let current = catalog.card(id) {
            entry = current
            isNoLongerInCatalog = false
        } else {
            entry = card.catalogCardID == nil ? nil : card.lastCatalogEntry
            isNoLongerInCatalog = entry != nil
        }
        pointValueCents = card.pointValueCents
    }

    /// The rates the Card earns on `today`, one per Reward category, best Effective rate first and Everything else
    /// last. Only the rules that apply to a category whatever is bought or how: rotating, chosen and top-spend rules,
    /// rules limited to a way of paying or to merchants, rules that need an answer from the cardholder and tier
    /// boosts are left out, and so are rules not in their dates on `today`.
    func rates(on today: CalendarDay) -> [CardRate] {
        guard let entry else { return [] }
        let order = Dictionary(uniqueKeysWithValues: RewardCategory.fixed.enumerated().map { ($1.id, $0) })
        var best: [String: CardRate] = [:]
        for rule in entry.rules where Self.isShown(rule, on: today) {
            for id in rule.categories {
                guard let reward = RewardCategory.fixed(id) else { continue }
                let rate = rate(of: rule, on: reward)
                if rate.effectiveRate > best[id]?.effectiveRate ?? -1 {
                    best[id] = rate
                }
            }
        }
        return best.values.sorted { lhs, rhs in
            let lhsLast = lhs.reward == .everythingElse, rhsLast = rhs.reward == .everythingElse
            if lhsLast != rhsLast { return rhsLast }
            if lhs.effectiveRate != rhs.effectiveRate { return lhs.effectiveRate > rhs.effectiveRate }
            return order[lhs.reward.id, default: .max] < order[rhs.reward.id, default: .max]
        }
    }

    /// A rule's rate on `reward`: points or miles per dollar are worth the Point value each, and a rate in percent is
    /// already an Effective rate, whatever kind of card states it.
    private func rate(of rule: CatalogRule, on reward: RewardCategory) -> CardRate {
        rule.unit == "per-dollar"
            ? CardRate(reward: reward, multiplier: rule.rate, effectiveRate: rule.rate * pointValueCents, rule: rule)
            : CardRate(reward: reward, multiplier: nil, effectiveRate: rule.rate, rule: rule)
    }

    /// Whether the Card's page shows `rule` on `today`: a fixed-category rule in its dates, with no condition the app
    /// can't tell from a purchase's category.
    static func isShown(_ rule: CatalogRule, on today: CalendarDay) -> Bool {
        guard rule.selection == "fixed", rule.paysWith == nil, rule.merchants.isEmpty, rule.tier == nil,
              rule.needs.isEmpty, rule.firstMonths == nil, !rule.requires.contains("preferred-rewards-tier")
        else { return false }
        if let from = rule.validFrom.flatMap(CalendarDay.init(isoDate:)), today < from { return false }
        if let to = rule.validTo.flatMap(CalendarDay.init(isoDate:)), to < today { return false }
        return true
    }
}

nonisolated extension CalendarDay {
    /// The day a `yyyy-MM-dd` date names, as the rewards catalog writes them; `nil` for anything else.
    init?(isoDate: String) {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }
}
