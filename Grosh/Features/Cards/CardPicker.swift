import CoreGraphics
import SwiftData
import SwiftUI

/// Picks a Card. A transaction's Card is picked from the unarchived Cards whose paying wallet is its wallet, in the
/// order they were added, or "None"; the current selection stays visible even when it was archived since (editing a
/// past transaction). Clear the selection when the transaction's wallet changes. A filter picks from every Card,
/// archived ones included, or none. Once an Expense's category is picked, a transaction's Cards are listed best first
/// for what that category earns, each with a second line saying what (``CardEarning``); picking the category never
/// picks a Card.
struct CardPicker: View {
    let title: LocalizedStringResource
    @Binding var selection: Card?
    /// The Cards of one wallet, or every Card.
    private let offered: Offered
    /// The first choice, which picks no Card.
    private let noneTitle: LocalizedStringResource

    @Query(Card.listed) private var listedCards: [Card]
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @Environment(\.displayScale) private var displayScale
    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today

    private enum Offered {
        /// The Cards paid from a wallet, ordered for what a purchase in the category earns when there is one.
        case paidFrom(Wallet?, category: Category?)
        case every
    }

    /// A transaction's Card: the unarchived Cards paid from `wallet`, or "None". With the transaction's `category`,
    /// best first for what it earns.
    init(title: LocalizedStringResource, wallet: Wallet?, category: Category? = nil, selection: Binding<Card?>) {
        self.title = title
        _selection = selection
        offered = .paidFrom(wallet, category: category)
        noneTitle = Strings.Common.none
    }

    /// Any Card, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringResource, everyCardOr noneTitle: LocalizedStringResource, selection: Binding<Card?>) {
        self.title = title
        _selection = selection
        offered = .every
        self.noneTitle = noneTitle
    }

    var body: some View {
        Picker(title, selection: $selection) {
            Text(noneTitle).tag(Card?.none)
            ForEach(choices) { choice in
                let card = choice.card
                Label {
                    Text(card.isArchived ? String(localized: Strings.Common.archivedName(card.displayName)) : card.displayName)
                    if let detail = choice.detail {
                        Text(detail)
                    }
                } icon: {
                    mark(of: card)
                }
                .tag(Optional(card))
            }
        }
    }

    /// The Cards offered, with what each earns, worked out once per draw.
    private var choices: [CardEarning] {
        switch offered {
        case .paidFrom(let wallet, let category):
            CardEarning.ordered(
                Card.pickerChoices(for: wallet, keeping: selection), for: category, in: catalog,
                own: ownRewardCategories.map(RewardCategory.init), on: today
            )
        case .every: listedCards.map { CardEarning(card: $0, rate: nil) }
        }
    }

    /// A Card's mark in the picker: its image as a small card 16 points tall, or its coloured symbol when it has none.
    private func mark(of card: Card) -> some View {
        CardMark(card: card, height: 16, shrunkForScale: displayScale)
    }
}
