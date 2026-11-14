import Foundation
import SwiftData

/// One rotating quarter a Card's page shows: its Reward categories, its rate and its dates, earned only between them
/// and, when it needs activating, only once the user marks it Activated.
nonisolated struct QuarterRate: Identifiable, Hashable, Sendable {
    /// The quarter's first day as the catalog writes it (`yyyy-MM-dd`), which Activated is kept by.
    let start: String
    let from: CalendarDay
    let to: CalendarDay
    let rewards: [RewardCategory]
    let rate: CardRate
    let needsActivation: Bool
    let isActivated: Bool
    /// Whether the day asked about is between its dates; otherwise it is still to come.
    let isCurrent: Bool
    /// The merchants it also earns at, besides its Reward categories.
    let merchants: [String]

    var id: String { "\(start) \(rewards.map(\.id).joined(separator: ","))" }

    /// Whether a purchase on a day between its dates earns it.
    var isEarned: Bool { isCurrent && (isActivated || !needsActivation) }
}

/// A rate whose Reward category the cardholder picks (Customized Cash) or that goes to the category the Card was used
/// most for (Custom Cash), with Your choice.
nonisolated struct ChoiceRate: Identifiable, Hashable, Sendable {
    /// What Your choice is kept by on the Card (``CatalogRule/choiceKey``).
    let key: String
    let isTopSpend: Bool
    /// How many Reward categories the cardholder picks.
    let picks: Int
    /// The Reward categories it can be on.
    let options: [RewardCategory]
    /// Your choice: what the user picked, empty while not set.
    let chosen: [RewardCategory]
    /// For a top-spend rate, the option the Card was used most for in its current period, if any.
    let topSpend: RewardCategory?
    let rate: CardRate

    var id: String { key }

    /// The Reward categories it earns on: Your choice, or for a top-spend rate with none, the top-spend category.
    var earnedOn: [RewardCategory] {
        if !chosen.isEmpty { return chosen }
        return isTopSpend ? topSpend.map { [$0] } ?? [] : []
    }

    /// Your choice once the user picks `option`: it alone for a rate with one pick; otherwise added, or taken away when
    /// already chosen. A rate with more picks keeps at most that many, so a pick past them is left out.
    func choosing(_ option: RewardCategory) -> [String] {
        let ids = chosen.map(\.id)
        if picks == 1 { return [option.id] }
        if ids.contains(option.id) { return ids.filter { $0 != option.id } }
        return ids.count < picks ? ids + [option.id] : ids
    }
}

/// Everything a Card's page shows it earns: the fixed rates per Reward category, the rotating quarters, the rates on
/// Your choice or the top-spend category, a rotating rate with no quarter dated yet, and rates limited to a way of
/// paying or to merchants, which are shown and never earned.
nonisolated struct CardRewardsPage {
    let rates: [CardRate]
    let quarters: [QuarterRate]
    let choices: [ChoiceRate]
    /// A rotating rate shown as "5% on rotating categories" while no quarter of it is current or coming. Never earned.
    let rotatingWithoutQuarter: CardRate?
    /// Rates paid a certain way or at certain merchants, which the app doesn't record. Never earned.
    let conditional: [CardRate]
}

/// What a purchase counting as a Reward category earns with a Card, as the Card picker shows it.
nonisolated struct PurchaseEarning: Hashable, Sendable {
    /// The Reward category whose rate it is: the purchase's own when any bonus covers it, else Everything else.
    let reward: RewardCategory
    let effectiveRate: Double
    /// Points or miles per dollar, for a points or miles Card whose every rate here is stated that way.
    let multiplier: Double?
    /// What it would earn once a current quarter covering it is Activated, when that is more.
    let activateFor: Double?
}

/// Why Your choice was refused.
nonisolated enum YourChoiceError: RuleRefusal, Equatable {
    /// Your choice is one of the rate's own Reward categories.
    case notAnOption
    /// The rate is earned on at most its number of picks.
    case tooMany
}

extension YourChoiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notAnOption: String(localized: Strings.Rewards.notAnOption)
        case .tooMany: String(localized: Strings.Rewards.tooManyChoices)
        }
    }
}

nonisolated extension CatalogRule {
    /// What a Card keeps Your choice for this rule by: its kind and the Reward categories it can be on, which no two
    /// such rules on a card share. Not its rate, so a newer catalog's corrected rate keeps the choice (ADR-0014).
    var choiceKey: String { "\(selection):\(categories.sorted().joined(separator: ","))" }
}

nonisolated extension CardRewards {
    /// Everything the Card's page shows on `today`. `spending` is what the Card paid in its current period per Reward
    /// category (``CardTopSpend/spending(of:on:in:)``), for a top-spend rate.
    func page(on today: CalendarDay, own: [RewardCategory] = [], spending: [String: Int] = [:]) -> CardRewardsPage {
        let rules = entry?.rules ?? []
        let quarters = quarterRates(on: today, own: own)
        let rotating = rules.first {
            $0.selection == "rotating" && $0.validFrom == nil && $0.validTo == nil && $0.isEarnableByCategory
        }
        return CardRewardsPage(
            rates: rates(on: today, own: own),
            quarters: quarters,
            choices: choiceRates(on: today, own: own, spending: spending),
            rotatingWithoutQuarter: quarters.isEmpty ? rotating.map { rate(of: $0, on: .everythingElse) } : nil,
            conditional: rules.filter { rule in
                (rule.paysWith != nil || (rule.selection == "fixed" && !rule.merchants.isEmpty)) && rule.tier == nil
                    && rule.isInDates(on: today)
            }.map { rate(of: $0, on: RewardCategory.fixed($0.categories.first ?? "") ?? .everythingElse) }
        )
    }

    /// What a purchase counting as `reward` earns with the Card on `today`: its Base rate (Everything else) and every
    /// bonus that covers it (a fixed rate, an earned quarter, Your choice, the top-spend category), added up as Base plus
    /// what each bonus adds over it when the card's Bonuses add up, else the best single one. `nil` for a Card with no
    /// rate that covers it.
    func earning(
        for reward: String, on today: CalendarDay, own: [RewardCategory] = [], spending: [String: Int] = [:]
    ) -> PurchaseEarning? {
        let fixed = rates(on: today, own: own)
        let base = fixed.first { $0.reward == .everythingElse }
        var bonuses = fixed.filter { $0.reward.id == reward && $0.reward != .everythingElse }
        bonuses += choiceRates(on: today, own: own, spending: spending)
            .filter { $0.earnedOn.contains { $0.id == reward } }.map(\.rate)
        let quarters = quarterRates(on: today, own: own).filter { $0.isCurrent && $0.rewards.contains { $0.id == reward } }
        let earned = combine(base: base, bonuses: bonuses + quarters.filter(\.isEarned).map(\.rate))
        guard let earned else { return nil }
        let unactivated = quarters.filter { !$0.isEarned }.map(\.rate)
        let activated = unactivated.isEmpty ? nil : combine(base: base, bonuses: bonuses + quarters.map(\.rate))
        let covered = bonuses.count + quarters.filter(\.isEarned).count > 0
        let name = RewardCategory.named(reward, in: RewardCategory.listed(own: own))
        return PurchaseEarning(
            reward: covered ? name : .everythingElse, effectiveRate: earned.effectiveRate, multiplier: earned.multiplier,
            activateFor: activated.flatMap { $0.effectiveRate > earned.effectiveRate ? $0.effectiveRate : nil }
        )
    }

    /// Whether the Card has a top-spend rate with no Your choice, so its current period's spending is needed.
    var needsSpending: Bool {
        (entry?.rules ?? []).contains { $0.selection == "top-spend" && (yourChoices[$0.choiceKey] ?? []).isEmpty }
    }

    /// Base plus what each bonus adds over it, when the card's Bonuses add up; otherwise the best single rate.
    private func combine(base: CardRate?, bonuses: [CardRate]) -> (effectiveRate: Double, multiplier: Double?)? {
        guard base != nil || !bonuses.isEmpty else { return nil }
        let baseRate = base?.effectiveRate ?? 0
        let total = entry?.bonusesStack == true
            ? baseRate + bonuses.map { max(0, $0.effectiveRate - baseRate) }.reduce(0, +)
            : ([baseRate] + bonuses.map(\.effectiveRate)).max() ?? baseRate
        let used = [base].compactMap(\.self) + bonuses
        let inPoints = rewardKind.earnsPoints && used.allSatisfy { $0.multiplier != nil } && pointValueCents > 0
        return (total, inPoints ? total / pointValueCents : nil)
    }

    private func quarterRates(on today: CalendarDay, own: [RewardCategory]) -> [QuarterRate] {
        let listed = RewardCategory.listed(own: own)
        return (entry?.rules ?? []).compactMap { rule -> QuarterRate? in
            guard rule.selection == "rotating", rule.isEarnableByCategory, let start = rule.validFrom,
                  let from = CalendarDay(isoDate: start), let to = rule.validTo.flatMap(CalendarDay.init(isoDate:)),
                  today <= to
            else { return nil }
            let rewards = listed.filter { rule.categories.contains($0.id) }
            return QuarterRate(
                start: start, from: from, to: to, rewards: rewards,
                rate: rate(of: rule, on: rewards.first ?? .everythingElse),
                needsActivation: rule.requires.contains("activation"), isActivated: activatedQuarters.contains(start),
                isCurrent: from <= today, merchants: rule.merchants
            )
        }.sorted { $0.from < $1.from }
    }

    private func choiceRates(on today: CalendarDay, own: [RewardCategory], spending: [String: Int]) -> [ChoiceRate] {
        let listed = RewardCategory.listed(own: own)
        return (entry?.rules ?? []).compactMap { rule -> ChoiceRate? in
            guard rule.selection == "choose" || rule.selection == "top-spend", rule.isEarnableByCategory,
                  rule.isInDates(on: today)
            else { return nil }
            let options = listed.filter { rule.categories.contains($0.id) }
            let chosen = options.filter { (yourChoices[rule.choiceKey] ?? []).contains($0.id) }
            let isTopSpend = rule.selection == "top-spend"
            let top = isTopSpend
                ? options.filter { (spending[$0.id] ?? 0) > 0 }.max { (spending[$0.id] ?? 0) < (spending[$1.id] ?? 0) }
                : nil
            return ChoiceRate(
                key: rule.choiceKey, isTopSpend: isTopSpend, picks: max(1, rule.picks ?? 1), options: options,
                chosen: chosen, topSpend: top, rate: rate(of: rule, on: chosen.first ?? top ?? .everythingElse)
            )
        }
    }
}

extension Card {
    /// The rotating quarters the user marked Activated, by each quarter's first day as the catalog writes it.
    var activatedQuarters: Set<String> {
        Set((activatedQuartersRaw ?? "").split(separator: ",").map(String.init))
    }

    /// Marks the quarter starting `start` Activated, or not. Saves.
    func setActivated(_ start: String, _ isActivated: Bool) throws {
        var quarters = activatedQuarters
        if isActivated {
            quarters.insert(start)
        } else {
            quarters.remove(start)
        }
        activatedQuartersRaw = quarters.isEmpty ? nil : quarters.sorted().joined(separator: ",")
        try saveToStore()
    }

    /// Your choice for each rate it was set for, by ``CatalogRule/choiceKey``.
    var yourChoices: [String: [String]] {
        guard let yourChoicesData else { return [:] }
        return Log.store.attempt("Reading a Card's Your choice") {
            try JSONDecoder().decode([String: [String]].self, from: yourChoicesData)
        } ?? [:]
    }

    /// Sets Your choice for the rate `key` names on the Card's entry in `catalog`: some of its own Reward categories, up
    /// to its picks, or none to unset it. Saves.
    @MainActor
    func setYourChoice(_ rewards: [String], for key: String, in catalog: RewardsCatalog) throws {
        let rule = CardRewards(of: self, in: catalog).entry?.rules.first { $0.choiceKey == key }
        guard let rule, rewards.allSatisfy(rule.categories.contains) else { throw YourChoiceError.notAnOption }
        guard rewards.count <= max(1, rule.picks ?? 1) else { throw YourChoiceError.tooMany }
        var choices = yourChoices
        choices[key] = rewards.isEmpty ? nil : rewards
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        yourChoicesData = choices.isEmpty ? nil : try encoder.encode(choices)
        try saveToStore()
    }
}
