import Foundation
import SwiftData

/// What one Card earns on a Reward category, as Best Card ranks it.
struct BestCardChoice: Identifiable {
    let card: Card
    let earning: PurchaseEarning

    var id: ObjectIdentifier { ObjectIdentifier(card) }
}

/// One Reward category's tile on Best Card.
struct BestCardTile: Identifiable {
    let reward: RewardCategory
    /// The Card the tile shows: the Go-to card, else the unarchived Card that earns the most on it; `nil` when no Card
    /// earns on it, which shows 0%.
    let shown: BestCardChoice?
    /// Whether ``shown`` is the user's Go-to card.
    let isGoTo: Bool
    /// Whether another Card earns more than the Go-to card and Needs nothing it doesn't, which flags the tile.
    let isBeaten: Bool

    var id: String { reward.id }
}

/// One row of a Reward category's list on Best Card: what a Card earns on it, or a rate of the Card's limited to stores.
struct BestCardRow: Identifiable {
    let card: Card
    let effectiveRate: Double
    /// Points or miles per dollar, for a rate stated that way.
    let multiplier: Double?
    let needs: [RateNeed]
    /// Whether the Card is the Go-to card for the Reward category.
    let isGoTo: Bool
    let id: String
}

/// Which Card earns the most on each Reward category, worked out once per draw from the unarchived Cards. Rates compete
/// as if what they Need is done, and nothing counts what was earned (ADR-0016).
@MainActor
struct BestCard {
    private let cards: [(card: Card, rewards: CardRewards, spending: [String: Int])]
    private let own: [RewardCategory]
    private let today: CalendarDay

    /// `cards` are the unarchived Cards in the user's order, which breaks ties. `spending` gives a Card's current
    /// period's spending, asked only of a Card with a top-spend rate and no Your choice.
    init(
        cards: [Card], catalog: RewardsCatalog, own: [RewardCategory], on today: CalendarDay,
        spending: (Card) -> [String: Int]
    ) {
        self.cards = cards.map { card in
            let rewards = CardRewards(of: card, in: catalog)
            return (card, rewards, rewards.needsSpending ? spending(card) : [:])
        }
        self.own = own
        self.today = today
    }

    /// What each Card earns on `reward`, best first, equal rates in the user's order; Cards that earn nothing on it are
    /// left out.
    func choices(for reward: String) -> [BestCardChoice] {
        let choices = cards.compactMap { card, rewards, spending in
            rewards.rankedEarning(for: [reward], on: today, own: own, spending: spending)
                .map { BestCardChoice(card: card, earning: $0) }
        }
        return choices.enumerated().sorted { lhs, rhs in
            if lhs.element.earning.effectiveRate != rhs.element.earning.effectiveRate {
                return lhs.element.earning.effectiveRate > rhs.element.earning.effectiveRate
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// `reward`'s tile: its Go-to card while that is unarchived and earns on it, flagged when another Card earns more
    /// and Needs nothing it doesn't; otherwise the Card that earns the most.
    func tile(for reward: RewardCategory) -> BestCardTile {
        let ranked = choices(for: reward.id)
        guard let goTo = ranked.first(where: { $0.card.goToRewards.contains(reward.id) }) else {
            return BestCardTile(reward: reward, shown: ranked.first, isGoTo: false, isBeaten: false)
        }
        let goToNeeds = Set(goTo.earning.needs)
        let isBeaten = ranked.contains {
            $0.earning.effectiveRate > goTo.earning.effectiveRate && Set($0.earning.needs).isSubset(of: goToNeeds)
        }
        return BestCardTile(reward: reward, shown: goTo, isGoTo: true, isBeaten: isBeaten)
    }

    /// Every Card's rate on `reward`, and the rates limited to stores, best first; on equal rates a Card's own comes
    /// before a store's, then the user's order.
    func rows(for reward: RewardCategory) -> [BestCardRow] {
        var rows: [(row: BestCardRow, isStore: Bool, order: Int)] = []
        for (order, entry) in cards.enumerated() {
            let isGoTo = entry.card.goToRewards.contains(reward.id)
            let cardID = "\(ObjectIdentifier(entry.card))"
            if let earning = entry.rewards.rankedEarning(for: [reward.id], on: today, own: own, spending: entry.spending) {
                let row = BestCardRow(
                    card: entry.card, effectiveRate: earning.effectiveRate, multiplier: earning.multiplier,
                    needs: earning.needs, isGoTo: isGoTo, id: "\(cardID)"
                )
                rows.append((row, false, order))
            }
            for (index, rate) in entry.rewards.storeRates(for: reward.id, on: today, own: own).enumerated() {
                let row = BestCardRow(
                    card: entry.card, effectiveRate: rate.effectiveRate,
                    multiplier: entry.rewards.rewardKind.earnsPoints ? rate.multiplier : nil, needs: rate.needs,
                    isGoTo: isGoTo, id: "\(cardID) store \(index)"
                )
                rows.append((row, true, order))
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.row.effectiveRate != rhs.row.effectiveRate { return lhs.row.effectiveRate > rhs.row.effectiveRate }
            if lhs.isStore != rhs.isStore { return !lhs.isStore }
            return lhs.order < rhs.order
        }.map(\.row)
    }
}

extension Card {
    /// The Reward categories the Card is the Go-to card for on Best Card, by id.
    var goToRewards: [String] {
        get { goToRewardsList ?? [] }
        set { goToRewardsList = newValue.isEmpty ? nil : newValue }
    }

    /// Makes the Card the Go-to card for `reward` on Best Card, in place of any other Card. Saves.
    func makeGoTo(for reward: String) throws {
        let context = try storeContext()
        for other in try context.fetch(FetchDescriptor<Card>()) where other !== self && other.goToRewards.contains(reward) {
            other.goToRewards.removeAll { $0 == reward }
        }
        if !goToRewards.contains(reward) { goToRewards.append(reward) }
        try context.save()
    }

    /// Stops the Card being the Go-to card for `reward`, so the tile shows the Card that earns the most. Saves.
    func removeGoTo(for reward: String) throws {
        goToRewards.removeAll { $0 == reward }
        try saveToStore()
    }
}

extension BestCard {
    /// Best Card on `today` from `cards`, with the user's `own` Reward categories, reading a top-spend Card's spending
    /// this period from `context` (``CardTopSpend``).
    init(cards: [Card], catalog: RewardsCatalog, own: [OwnRewardCategory], on today: CalendarDay, in context: ModelContext) {
        self.init(
            cards: cards, catalog: catalog, own: own.map(RewardCategory.init), on: today,
            spending: { CardTopSpend.spendingOrNone(of: $0, on: today, in: context) }
        )
    }
}
