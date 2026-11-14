import CoreGraphics
import SwiftData
import SwiftUI

/// Picks a Card. A transaction's Card is picked from a list it pushes: the unarchived Cards whose paying wallet is its
/// wallet, in the order they were added, or "None"; the current selection stays visible even when it was archived
/// since (editing a past transaction). Once an Expense's category is picked, they are listed best first for what that
/// category earns, each with a second line saying what (``CardEarning``), and the row says what the picked Card earns;
/// picking the category never picks a Card. What each earns is worked out for the transaction's own day. Clear the
/// selection when the transaction's wallet changes. A filter picks from a menu of every Card, archived ones included, or
/// none.
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
    @Environment(\.modelContext) private var context
    @StoreSaves private var saves
    /// The Cards with what each earns, kept until what they were worked out from changes or the store saves
    /// (``CardChoicesKey``), so a top-spend Card's spending isn't fetched again on every keystroke in the form.
    @State private var keptChoices = DrawingCache<CardChoicesKey, [CardEarning]>()

    private enum Offered {
        /// The Cards paid from a wallet, ordered for what a purchase in the category on the day earns when there is one.
        case paidFrom(Wallet?, category: Category?, day: CalendarDay?)
        case every
    }

    /// A transaction's Card: the unarchived Cards paid from `wallet`, or "None". With the transaction's `category`,
    /// best first for what it earns on `day`, the transaction's own (today when not given).
    init(
        title: LocalizedStringResource, wallet: Wallet?, category: Category? = nil, day: CalendarDay? = nil,
        selection: Binding<Card?>
    ) {
        self.title = title
        _selection = selection
        offered = .paidFrom(wallet, category: category, day: day)
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
        case .paidFrom(let wallet, let category, let day):
            let choices = keptChoices.value(for: key(wallet: wallet, category: category, day: day ?? today)) {
                CardChoicesKey.choices(
                    wallet: wallet, category: category, selection: selection, day: day ?? today, catalog: catalog,
                    own: ownRewardCategories, context: context
                )
            }
            NavigationLink {
                CardChoiceList(title: title, wallet: wallet, category: category, day: day ?? today, selection: $selection)
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
        listedCards.map { CardEarning(card: $0, earning: nil) }
    }

    private func key(wallet: Wallet?, category: Category?, day: CalendarDay) -> CardChoicesKey {
        CardChoicesKey(
            wallet: wallet?.persistentModelID, category: category?.persistentModelID,
            selection: selection?.persistentModelID, day: day, own: ownRewardCategories.map(\.persistentModelID),
            saves: saves
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
    let day: CalendarDay
    @Binding var selection: Card?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @Environment(\.rewardsCatalog) private var catalog
    @Query(RewardCategories.ownInOrder) private var ownRewardCategories: [OwnRewardCategory]
    @Environment(\.modelContext) private var context
    @StoreSaves private var saves
    @State private var keptChoices = DrawingCache<CardChoicesKey, [CardEarning]>()

    var body: some View {
        // Worked out here rather than handed over by the form, which redraws as the list goes back, and kept until what
        // it was worked out from changes or the store saves.
        let key = CardChoicesKey(
            wallet: wallet?.persistentModelID, category: category?.persistentModelID,
            selection: selection?.persistentModelID, day: day, own: ownRewardCategories.map(\.persistentModelID),
            saves: saves
        )
        let choices = keptChoices.value(for: key) {
            CardChoicesKey.choices(
                wallet: wallet, category: category, selection: selection, day: day, catalog: catalog,
                own: ownRewardCategories, context: context
            )
        }
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

/// What a transaction's Card choices were worked out from: a ``DrawingCache`` key, so they are worked out again when the
/// wallet, category, picked Card, day or the user's own Reward categories change, or the store saves (Your choice, a
/// rate or a transaction).
private struct CardChoicesKey: Equatable {
    let wallet: PersistentIdentifier?
    let category: PersistentIdentifier?
    let selection: PersistentIdentifier?
    let day: CalendarDay
    let own: [PersistentIdentifier]
    let saves: Int

    /// The Cards offered on `wallet`'s transactions, with what a purchase in `category` on `day` earns with each.
    @MainActor
    static func choices(
        wallet: Wallet?, category: Category?, selection: Card?, day: CalendarDay, catalog: RewardsCatalog,
        own: [OwnRewardCategory], context: ModelContext
    ) -> [CardEarning] {
        CardEarning.ordered(
            Card.pickerChoices(for: wallet, keeping: selection), for: category, in: catalog,
            own: own.map(RewardCategory.init), on: day,
            spending: { CardTopSpend.spendingOrNone(of: $0, on: day, in: context) }
        )
    }
}
