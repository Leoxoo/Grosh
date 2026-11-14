import CoreGraphics
import SwiftData
import SwiftUI

/// Picks a Card. A transaction's Card is picked from a list it pushes: the unarchived Cards whose paying wallet is its
/// wallet, in the order they were added, or "None"; the current selection stays visible even when it was archived
/// since (editing a past transaction). Once an Expense's category is picked, they are listed best first for what that
/// category earns, each with a second line saying what (``CardEarning``), and the row says what the picked Card earns;
/// picking the category never picks a Card. Clear the selection when the transaction's wallet changes. A filter picks
/// from a menu of every Card, archived ones included, or none.
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
        switch offered {
        case .paidFrom(let wallet, let category):
            let choices = transactionChoices(wallet: wallet, category: category)
            NavigationLink {
                CardChoiceList(title: title, wallet: wallet, category: category, selection: $selection)
            } label: {
                LabeledContent(title) {
                    if let selection {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(selection.displayName)
                                .foregroundStyle(.primary)
                            if let detail = choices.first(where: { $0.card == selection })?.detail {
                                Text(detail)
                                    .font(.footnote)
                            }
                        }
                    } else {
                        Text(noneTitle)
                    }
                }
            }
        case .every:
            menu
        }
    }

    /// A filter's choice: a menu of every Card.
    private var menu: some View {
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

    /// A filter's Cards: every one, archived ones included.
    private var choices: [CardEarning] {
        listedCards.map { CardEarning(card: $0, rate: nil) }
    }

    /// A transaction's Cards, with what each earns, worked out once per draw.
    private func transactionChoices(wallet: Wallet?, category: Category?) -> [CardEarning] {
        CardEarning.ordered(
            Card.pickerChoices(for: wallet, keeping: selection), for: category, in: catalog,
            own: ownRewardCategories.map(RewardCategory.init), on: today
        )
    }

    /// A Card's mark in the picker: its image as a small card 16 points tall, or its coloured symbol when it has none.
    private func mark(of card: Card) -> some View {
        CardMark(card: card, height: 16, shrunkForScale: displayScale)
    }
}

/// The list a transaction's ``CardPicker`` pushes: "None", then the Cards in the order given, each with its mark, its
/// name and, when the category earns on it, a second line saying what. Picking one goes back.
private struct CardChoiceList: View {
    let title: LocalizedStringResource
    let wallet: Wallet?
    let category: Category?
    @Binding var selection: Card?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.rewardsCatalog) private var catalog
    @Environment(\.today) private var today
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]

    var body: some View {
        // Worked out here, once per draw, rather than handed over by the form, which redraws as the list goes back.
        let choices = CardEarning.ordered(
            Card.pickerChoices(for: wallet, keeping: selection), for: category, in: catalog,
            own: ownRewardCategories.map(RewardCategory.init), on: today
        )
        List {
            Section {
                row(nil, detail: nil)
                ForEach(choices) { choice in
                    row(choice.card, detail: choice.detail)
                }
            }
        }
        .navigationTitle(title)
    }

    private func row(_ card: Card?, detail: String?) -> some View {
        Button {
            selection = card
            dismiss()
        } label: {
            HStack(spacing: 12) {
                if let card {
                    CardMark(card: card, height: 16, shrunkForScale: displayScale)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.map { $0.isArchived ? String(localized: Strings.Common.archivedName($0.displayName)) : $0.displayName }
                        ?? String(localized: Strings.Common.none))
                    if let detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if card == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(card == selection ? .isSelected : [])
    }
}
