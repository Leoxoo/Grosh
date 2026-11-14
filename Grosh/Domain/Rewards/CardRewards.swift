import Foundation
import SwiftData

/// One rate a Card earns on a Reward category, as its page lists it.
nonisolated struct CardRate: Identifiable, Hashable, Sendable {
    let reward: RewardCategory
    /// Points or miles per dollar, for a rate stated that way; `nil` for cash back, whose rate is already an Effective
    /// rate.
    let multiplier: Double?
    /// What the Card earns as a share of what was spent, in percent: a cash back rate as it is, a points or miles rate
    /// times the Card's Point value. Rates are compared and sorted by it.
    let effectiveRate: Double
    let cap: RateCap?
    /// The first and last days it earns, where it has them.
    let validFrom: CalendarDay?
    let validTo: CalendarDay?
    /// The catalog's rule it comes from, with its requirements, conditions and quote; `nil` for a rate the user entered.
    let rule: CatalogRule?
    /// Whether it is an Edited rate: one the user entered on a linked Card in place of the catalog's.
    let isEdited: Bool

    var id: String { reward.id }
}

/// A Reward category a Card has a rate for, as the rate editor lists it: the catalog's rate today, what the user
/// entered in its place, or both.
nonisolated struct EditableRate: Identifiable, Hashable, Sendable {
    let reward: RewardCategory
    /// The rate the catalog gives the Card for it today, if any.
    let catalog: CardRate?
    /// What the user entered for it: a rate, or a removal of the catalog's.
    let entered: EnteredRate?
    /// The rate the Card earns for it, as its page shows it: the entered one, else the catalog's; `nil` once removed.
    let shown: CardRate?

    var id: String { reward.id }

    /// Whether Reset to catalog applies: the user entered a rate, or a removal, in place of a linked Card's catalog rate.
    var canReset: Bool { entered != nil && catalog != nil }
}

/// What a Card earns: the catalog entry it is linked to, from the catalog the app ships, or from the rates the entry
/// last had when a newer catalog no longer has it (ADR-0014), with the rates the user entered on top.
nonisolated struct CardRewards {
    /// The catalog entry, or `nil` for a Card that isn't linked.
    let entry: CatalogCard?
    /// Whether the Card is linked to an entry the catalog no longer has, so ``entry`` is the one it last saw, marked "No
    /// longer in the catalog".
    let isNoLongerInCatalog: Bool
    let pointValueCents: Double
    /// What the Card earns: its entry's kind, else what the user set for a Custom card, else cash back.
    let rewardKind: RewardKind
    /// A Custom card's rates, or a linked Card's Edited rates and removals.
    let enteredRates: [EnteredRate]

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
        rewardKind = entry?.rewardKind ?? card.ownRewardKind ?? .cashback
        enteredRates = card.enteredRates
    }

    /// The rates the Card earns on `today`, one per Reward category, best Effective rate first and Everything else
    /// last: the catalog's (``catalogRates(on:)``) with each one the user entered in place of the catalog's for its
    /// category, and none for a category whose rate they removed. A rate the user entered earns between its dates (the
    /// catalog's earns outside them), and on one of their `own` Reward categories only while that still exists.
    func rates(on today: CalendarDay, own: [RewardCategory] = []) -> [CardRate] {
        Self.sorted(editable(on: today, own: own).compactMap { row in
            // An entered rate outside its dates leaves the catalog's rate, if any, to earn.
            guard let entered = row.entered, !entered.isRemoval, !entered.applies(on: today) else { return row.shown }
            return row.catalog
        }, own: own)
    }

    /// What a purchase counting as `reward` earns with the Card on `today`: its rate for that Reward category, else its
    /// rate for Everything else, else `nil` for a Card with no rates that cover it.
    func earning(for reward: String, on today: CalendarDay, own: [RewardCategory] = []) -> CardRate? {
        let rates = rates(on: today, own: own)
        return rates.first { $0.reward.id == reward } ?? rates.first { $0.reward == .everythingElse }
    }

    /// Every Reward category the Card has a rate for, the catalog's today or one the user entered whatever its dates,
    /// in the order ``rates(on:own:)`` lists them, removed ones last.
    func editable(on today: CalendarDay, own: [RewardCategory] = []) -> [EditableRate] {
        let catalog = catalogRates(on: today)
        let rewards = RewardCategory.listed(own: own)
        let entered = Dictionary(enteredRates.map { ($0.reward, $0) }, uniquingKeysWith: { _, last in last })
        let rows = rewards.compactMap { reward -> EditableRate? in
            let catalogRate = catalog[reward.id]
            let enteredRate = entered[reward.id]
            guard catalogRate != nil || enteredRate != nil else { return nil }
            let shown: CardRate? = switch enteredRate {
            case nil: catalogRate
            case let rate? where rate.isRemoval: nil
            case let rate?: self.rate(of: rate, on: reward)
            }
            return EditableRate(reward: reward, catalog: catalogRate, entered: enteredRate, shown: shown)
        }
        let shownOrder = Self.sorted(rows.compactMap(\.shown), own: own).map(\.reward.id)
        let position = Dictionary(uniqueKeysWithValues: shownOrder.enumerated().map { ($1, $0) })
        return rows.sorted { position[$0.reward.id, default: .max] < position[$1.reward.id, default: .max] }
    }

    /// Whether the Card's entry has a rate for `reward` that the page could show, whatever its dates, so removing it
    /// needs a removal kept on the Card.
    func catalogCovers(_ reward: String) -> Bool {
        entry?.rules.contains { Self.isShown($0, on: nil) && $0.categories.contains(reward) } == true
    }

    /// The catalog's rates for the Card on `today`, best per Reward category. Only the rules that apply to a category
    /// whatever is bought or how: rotating, chosen and top-spend rules, rules limited to a way of paying or to
    /// merchants, rules that need an answer from the cardholder and tier boosts are left out, and so are rules not in
    /// their dates on `today`.
    func catalogRates(on today: CalendarDay) -> [String: CardRate] {
        var best: [String: CardRate] = [:]
        for rule in entry?.rules ?? [] where Self.isShown(rule, on: today) {
            for id in rule.categories {
                guard let reward = RewardCategory.fixed(id) else { continue }
                let rate = rate(of: rule, on: reward)
                if rate.effectiveRate > best[id]?.effectiveRate ?? -1 {
                    best[id] = rate
                }
            }
        }
        return best
    }

    /// Best Effective rate first and Everything else last; equal rates in list order.
    private static func sorted(_ rates: [CardRate], own: [RewardCategory]) -> [CardRate] {
        let order = Dictionary(
            RewardCategory.listed(own: own).enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return rates.sorted { lhs, rhs in
            let lhsLast = lhs.reward == .everythingElse, rhsLast = rhs.reward == .everythingElse
            if lhsLast != rhsLast { return rhsLast }
            if lhs.effectiveRate != rhs.effectiveRate { return lhs.effectiveRate > rhs.effectiveRate }
            return order[lhs.reward.id, default: .max] < order[rhs.reward.id, default: .max]
        }
    }

    /// A rule's rate on `reward`: points or miles per dollar are worth the Point value each, and a rate in percent is
    /// already an Effective rate, whatever kind of card states it.
    private func rate(of rule: CatalogRule, on reward: RewardCategory) -> CardRate {
        let perDollar = rule.unit == "per-dollar"
        return CardRate(
            reward: reward, multiplier: perDollar ? rule.rate : nil,
            effectiveRate: perDollar ? rule.rate * pointValueCents : rule.rate,
            cap: rule.capAmount != nil || rule.capUnknown
                ? RateCap(
                    amount: rule.capAmount, period: RateCapPeriod(catalog: rule.capPeriod), isUnknown: rule.capUnknown,
                    currencyCode: "USD"
                )
                : nil,
            validFrom: rule.validFrom.flatMap(CalendarDay.init(isoDate:)),
            validTo: rule.validTo.flatMap(CalendarDay.init(isoDate:)),
            rule: rule, isEdited: false
        )
    }

    /// A rate the user entered, stated as the Card earns: points or miles per dollar for a points Card, else percent.
    private func rate(of entered: EnteredRate, on reward: RewardCategory) -> CardRate {
        let value = entered.rate ?? 0
        let points = rewardKind.earnsPoints
        return CardRate(
            reward: reward, multiplier: points ? value : nil, effectiveRate: points ? value * pointValueCents : value,
            cap: entered.cap, validFrom: entered.from, validTo: entered.to, rule: nil, isEdited: entry != nil
        )
    }

    /// Whether the Card's page shows `rule` on `today` (any day, for `nil`): a fixed-category rule in its dates, with
    /// no condition the app can't tell from a purchase's category.
    static func isShown(_ rule: CatalogRule, on today: CalendarDay?) -> Bool {
        guard rule.selection == "fixed", rule.paysWith == nil, rule.merchants.isEmpty, rule.tier == nil,
              rule.needs.isEmpty, rule.firstMonths == nil, !rule.requires.contains("preferred-rewards-tier")
        else { return false }
        guard let today else { return true }
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
