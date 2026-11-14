import Foundation

/// One Card in an Expense's Card picker, with what a purchase in the picked category earns with it.
nonisolated struct CardEarning: Identifiable {
    let card: Card
    /// The Card's rate for the category's Reward category, else its Everything else rate; `nil` when it has neither,
    /// or no category is picked.
    let rate: CardRate?

    var id: ObjectIdentifier { ObjectIdentifier(card) }

    /// The picker's second line: "3% · Dining" for cash back, "3× · 3% · Dining" for points or miles.
    var detail: String? {
        guard let rate else { return nil }
        let multiplier = rate.multiplier.map { String(localized: Strings.Rewards.multiplier(CardRateText.number($0))) }
        return [multiplier, CardRateText.percent(rate.effectiveRate), rate.reward.name]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// `cards`, the ones the picker offers in the user's order, best first for what a purchase in `category` earns on
    /// `today`: by Effective rate, equal rates and Cards without a rate in the order given. With no category, or one
    /// with no Rewards as (not an Expense), they stay as given with no rates. Each Card's rates are worked out once
    /// here, not per row.
    @MainActor
    static func ordered(
        _ cards: [Card], for category: Category?, in catalog: RewardsCatalog, own: [RewardCategory], on today: CalendarDay
    ) -> [CardEarning] {
        guard let reward = category?.rewardsAs else { return cards.map { CardEarning(card: $0, rate: nil) } }
        let earnings = cards.map { card in
            CardEarning(card: card, rate: CardRewards(of: card, in: catalog).earning(for: reward, on: today, own: own))
        }
        return earnings.enumerated().sorted { lhs, rhs in
            switch (lhs.element.rate?.effectiveRate, rhs.element.rate?.effectiveRate) {
            case let (left?, right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
