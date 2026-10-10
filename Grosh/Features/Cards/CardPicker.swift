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
                    Image(systemName: Card.symbolName)
                        .foregroundStyle(card.color.color)
                }
                .tag(Optional(card))
            }
        }
    }

    private var choices: [Card] {
        switch offered {
        case .paidFrom(let wallet): Card.pickerChoices(for: wallet, keeping: selection)
        case .every: allCards
        }
    }
}
