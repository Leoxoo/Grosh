import SwiftData
import SwiftUI

/// Best Card as the screens show it (``BestCard``): worked out from the unarchived Cards once per save of the view's
/// context, and again when the Cards, the user's own Reward categories or the day change. Its projected value is every
/// Reward category in list order, the user's own included.
@propertyWrapper
struct CurrentBestCard: DynamicProperty {
    @Query(Card.unarchived) private var cards: [Card]
    @Query(RewardCategories.ownInOrder) private var own: [OwnRewardCategory]
    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today
    @Environment(\.modelContext) private var context
    @StoreSaves private var saves
    @State private var kept = DrawingCache<Key, BestCard>()

    var wrappedValue: BestCard {
        let key = Key(cards: AsSaved(cards, saves: saves), own: own.map(\.persistentModelID), today: today)
        return kept.value(for: key) {
            BestCard(cards: cards, catalog: catalog, own: own, on: today, in: context)
        }
    }

    var projectedValue: [RewardCategory] {
        RewardCategory.listed(own: own.map(RewardCategory.init))
    }

    /// What Best Card was worked out from: the Cards and the saves counted then (a Go-to card, a rate, Your choice or a
    /// transaction), the user's own Reward categories and the day.
    private struct Key: Equatable {
        let cards: AsSaved
        let own: [PersistentIdentifier]
        let today: CalendarDay
    }
}
