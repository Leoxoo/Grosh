import CoreGraphics
import SwiftData
import SwiftUI

/// Picks a Card. A transaction's Card is picked from the unarchived Cards whose paying wallet is its wallet, in the
/// order they were added, or "None"; the current selection stays visible even when it was archived since (editing a
/// past transaction). Clear the selection when the transaction's wallet changes. A filter picks from every Card,
/// archived ones included, or none.
struct CardPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Card?
    /// The Cards of one wallet, or every Card.
    private let offered: Offered
    /// The first choice, which picks no Card.
    private let noneTitle: LocalizedStringKey

    @Query(sort: Card.userOrder) private var allCards: [Card]

    private enum Offered {
        case paidFrom(Wallet?)
        case every
    }

    /// A transaction's Card: the unarchived Cards paid from `wallet`, or "None".
    init(title: LocalizedStringKey, wallet: Wallet?, selection: Binding<Card?>) {
        self.title = title
        _selection = selection
        offered = .paidFrom(wallet)
        noneTitle = "None"
    }

    /// Any Card, archived ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringKey, everyCardOr noneTitle: LocalizedStringKey, selection: Binding<Card?>) {
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
                    Text(card.isArchived ? "\(card.displayName) (Archived)" : card.displayName)
                } icon: {
                    PickerCardMark(card: card)
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
}

/// A Card's mark in the picker: its image as a small card 16 points tall, or its coloured symbol when it has none. The
/// image is a copy shrunk to that size for this screen and drawn at its own size, never resized, because a picker's
/// label and menu rows ignore a frame and would draw a full-size image at full size.
private struct PickerCardMark: View {
    let card: Card

    @Environment(\.displayScale) private var displayScale

    private let height: CGFloat = 16

    var body: some View {
        if let image = card.shrunkImage(height: height, scale: displayScale) {
            Image(decorative: image, scale: displayScale)
                .clipShape(
                    RoundedRectangle(cornerRadius: height * CropShape.creditCard.cornerRatio, style: .continuous)
                )
                .accessibilityHidden(true)
        } else {
            Image(systemName: Card.symbolName)
                .foregroundStyle(card.color.color)
        }
    }
}
