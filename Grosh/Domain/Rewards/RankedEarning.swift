import Foundation

/// What a rate asks of a purchase beyond its Reward category, shown beside it wherever Cards are ranked. A rate competes
/// as if what it Needs is done: Grosh never records how a purchase was paid, and never counts what was earned
/// (ADR-0016).
nonisolated enum RateNeed: Hashable, Sendable {
    /// A way of paying, such as Apple Pay.
    case paysWith(String)
    /// The stores it is limited to, such as Amazon.
    case store([String])
    /// The bank asks the cardholder to activate it, such as a rotating quarter.
    case activation
}

nonisolated extension PurchaseEarning {
    /// What it Needs: the way of paying its rate is limited to, and activation when the bank asks for it on a rate it is
    /// made of.
    var needs: [RateNeed] {
        var needs = paysWith.map { [RateNeed.paysWith($0)] } ?? []
        if parts.contains(where: { $0.rate.rule?.requires.contains("activation") == true }) { needs.append(.activation) }
        return needs
    }
}

nonisolated extension CardRate {
    /// What it Needs, as Best Card lists it: its way of paying, its stores, activation.
    var needs: [RateNeed] {
        guard let rule else { return [] }
        var needs: [RateNeed] = []
        if let paysWith = rule.paysWith { needs.append(.paysWith(paysWith)) }
        if !rule.merchants.isEmpty { needs.append(.store(rule.merchants)) }
        if rule.requires.contains("activation") { needs.append(.activation) }
        return needs
    }
}

nonisolated extension CardRewards {
    /// What a purchase counting as each of `rewards` earns with the Card wherever Cards are ranked (Best Card and the
    /// Card picker): ``earning(for:on:own:spending:)``, or a rate limited to a way of paying when that earns more, as if
    /// the purchase is paid that way (ADR-0016). `nil` for a Card with no rate that covers any of them.
    func rankedEarning(
        for rewards: [String], on today: CalendarDay, own: [RewardCategory] = [], spending: [String: Int] = [:]
    ) -> PurchaseEarning? {
        let earned = earning(for: rewards, on: today, own: own, spending: spending)
        guard let paid = paidWithEarning(for: rewards, on: today, own: own),
              paid.effectiveRate > earned?.effectiveRate ?? -.infinity
        else { return earned }
        return paid
    }

    /// The best rate limited to a way of paying that covers a purchase counting as any of `rewards`: one on a Reward
    /// category among them, or on Everything else, which covers every purchase. `nil` when the Card has none.
    func paidWithEarning(for rewards: [String], on today: CalendarDay, own: [RewardCategory] = []) -> PurchaseEarning? {
        let listed = RewardCategory.listed(own: own)
        var best: PurchaseEarning?
        for rule in entry?.rules ?? [] where Self.isPaidWith(rule, on: today) {
            let covered = rewards.first(where: rule.categories.contains)
                ?? (rule.categories.contains(RewardCategory.everythingElse.id) ? RewardCategory.everythingElse.id : nil)
            guard let covered else { continue }
            let rate = rate(of: rule, on: RewardCategory.named(covered, in: listed))
            guard rate.effectiveRate > best?.effectiveRate ?? -.infinity else { continue }
            best = PurchaseEarning(
                reward: rate.reward, effectiveRate: rate.effectiveRate,
                multiplier: rewardKind.earnsPoints ? rate.multiplier : nil,
                parts: [EarningPart(rate: rate, adds: rate.effectiveRate, quarter: nil)], paysWith: rule.paysWith
            )
        }
        return best
    }

    /// The Card's rates on `reward` limited to stores ("5% at Amazon"), as Best Card lists them under a Reward category.
    /// They are never a tile's card, since the tile stands for every purchase in its Reward category (ADR-0016).
    func storeRates(for reward: String, on today: CalendarDay, own: [RewardCategory] = []) -> [CardRate] {
        let named = RewardCategory.named(reward, in: RewardCategory.listed(own: own))
        return (entry?.rules ?? []).filter { rule in
            rule.selection == "fixed" && !rule.merchants.isEmpty && rule.paysWith == nil && rule.tier == nil
                && rule.needs.isEmpty && rule.firstMonths == nil && rule.categories.contains(reward)
                && rule.isInDates(on: today)
        }.map { rate(of: $0, on: named) }
    }

    /// Whether `rule` is a rate limited to a way of paying, and nothing else the app can't tell, that applies on
    /// `today`.
    static func isPaidWith(_ rule: CatalogRule, on today: CalendarDay) -> Bool {
        rule.paysWith != nil && rule.selection == "fixed" && rule.merchants.isEmpty && rule.tier == nil
            && rule.needs.isEmpty && rule.firstMonths == nil && !rule.requires.contains("preferred-rewards-tier")
            && rule.isInDates(on: today)
    }
}
