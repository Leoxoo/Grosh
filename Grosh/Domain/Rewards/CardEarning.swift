import Foundation

/// One Card in an Expense's Card picker, with what a purchase in the picked category earns with it.
nonisolated struct CardEarning: Identifiable {
    let card: Card
    /// What a purchase in the category earns with the Card (``CardRewards/earning(for:on:own:spending:)``); `nil` when it
    /// has no rate that covers it, or no category is picked.
    let earning: PurchaseEarning?

    var id: ObjectIdentifier { ObjectIdentifier(card) }

    /// The picker's second line: "3% · Dining" for cash back, "3× · 3% · Dining" for points or miles.
    var detail: String? {
        guard let earning else { return nil }
        let multiplier = earning.multiplier.map { String(localized: Strings.Rewards.multiplier(CardRateText.number($0))) }
        return [multiplier, CardRateText.percent(earning.effectiveRate), earning.reward.name]
            .compactMap(\.self).joined(separator: " · ")
    }

    /// `cards`, the ones the picker offers in the user's order, best first for what a purchase in `category` earns on
    /// `day`, the purchase's own: by Effective rate, equal rates and Cards without a rate in the order given. With no category, or one
    /// with no Rewards as (not an Expense), they stay as given with no rates. Each Card's rates are worked out once
    /// here, not per row; `spending` gives a Card's current period's spending, asked only of a Card with a top-spend
    /// rate and no Your choice.
    @MainActor
    static func ordered(
        _ cards: [Card], for category: Category?, in catalog: RewardsCatalog, own: [RewardCategory], on day: CalendarDay,
        spending: (Card) -> [String: Int]
    ) -> [CardEarning] {
        guard let reward = category?.rewardsAs else { return cards.map { CardEarning(card: $0, earning: nil) } }
        let earnings = cards.map { card in
            let rewards = CardRewards(of: card, in: catalog)
            let spent = rewards.needsSpending ? spending(card) : [:]
            return CardEarning(card: card, earning: rewards.earning(for: reward, on: day, own: own, spending: spent))
        }
        return earnings.enumerated().sorted { lhs, rhs in
            switch (lhs.element.earning?.effectiveRate, rhs.element.earning?.effectiveRate) {
            case let (left?, right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}
