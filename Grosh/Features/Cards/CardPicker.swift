import CoreGraphics
import SwiftData
import SwiftUI

/// Picks a Card. A transaction's Card is picked from the unarchived Cards whose paying wallet is its wallet, in the
/// order they were added, or "None"; the current selection stays visible even when it was archived since (editing a
/// past transaction). Clear the selection when the transaction's wallet changes. A filter picks from every Card,
/// archived ones included, or none.
struct CardPicker: View {
    let title: LocalizedStringResource
    @Binding var selection: Card?
    /// The Cards of one wallet, or every Card.
    private let offered: Offered
    /// The first choice, which picks no Card.
    private let noneTitle: LocalizedStringResource

    @Query(sort: Card.userOrder) private var allCards: [Card]
    @Environment(\.displayScale) private var displayScale

    private enum Offered {
        case paidFrom(Wallet?)
        case every
    }

    /// A transaction's Card: the unarchived Cards paid from `wallet`, or "None".
    init(title: LocalizedStringResource, wallet: Wallet?, selection: Binding<Card?>) {
        self.title = title
        _selection = selection
        offered = .paidFrom(wallet)
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
            ForEach(choices) { card in
                Label {
                    Text(card.isArchived ? String(localized: Strings.Common.archivedName(card.displayName)) : card.displayName)
                } icon: {
                    mark(of: card)
                }
                .tag(Optional(card))
            }
        }
    }

    private var choices: [Card] {
        switch offered {
        case .paidFrom(let wallet): Card.pickerChoices(for: wallet, keeping: selection)
        case .every: allCards.filter { !$0.isPaidFromDeletedWallet }
        }
    }

    /// A Card's mark in the picker: its image as a small card 16 points tall, or its coloured symbol when it has none.
    /// The image is a copy shrunk to that size for this screen, drawn at its own size since a picker ignores a frame.
    private func mark(of card: Card) -> some View {
        let height: CGFloat = 16
        return CardMark(
            image: card.shrunkImage(height: height, scale: displayScale),
            height: height,
            sizing: .shrunk(scale: displayScale)
        ) {
            Image(systemName: Card.symbolName)
                .foregroundStyle(card.color.color)
        }
    }
}
