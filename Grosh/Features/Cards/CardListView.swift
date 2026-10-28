import SwiftData
import SwiftUI

/// Account → Cards: every Card in the order it was added. Tap to see its transactions by statement period or month,
/// swipe to archive.
struct CardListView: View {
    @Query(filter: #Predicate<Card> { !$0.isArchived }, sort: Card.userOrder) private var unarchivedCards: [Card]
    @Query(filter: #Predicate<Card> { $0.isArchived }, sort: Card.userOrder) private var allArchivedCards: [Card]
    @State private var editorMode: EditorMode<Card>?
    @State private var mergeSource: Card?
    @State private var errorMessage: String?

    /// The unarchived Cards, leaving out those whose paying wallet is in Recently Deleted.
    private var cards: [Card] { unarchivedCards.filter { !$0.isPaidFromDeletedWallet } }
    /// The archived Cards, leaving out those whose paying wallet is in Recently Deleted.
    private var archivedCards: [Card] { allArchivedCards.filter { !$0.isPaidFromDeletedWallet } }

    var body: some View {
        List {
            Section {
                ForEach(cards) { card in
                    row(card)
                        .swipeActions {
                            Button(Strings.Common.archive, systemImage: "archivebox") { perform { try card.archive() } }
                                .tint(.archiveAction)
                        }
                }
            } footer: {
                if !cards.isEmpty {
                    Text(Strings.Cards.onlyALabelListFooter)
                }
            }

            if !archivedCards.isEmpty {
                Section {
                    ForEach(archivedCards) { card in
                        row(card)
                            .foregroundStyle(.secondary)
                            .swipeActions {
                                Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") { perform { try card.unarchive() } }
                                    .tint(.unarchiveAction)
                            }
                    }
                } header: {
                    Text(Strings.Common.archived)
                } footer: {
                    Text(Strings.Cards.archivedSectionFooter)
                }
            }
        }
        .overlay {
            if cards.isEmpty && archivedCards.isEmpty {
                ContentUnavailableView {
                    Label(Strings.Cards.noCards, systemImage: "creditcard")
                } description: {
                    Text(Strings.Cards.noCardsDescription)
                } actions: {
                    Button(Strings.Cards.addCard) { editorMode = .add }
                }
            }
        }
        .navigationTitle(Strings.Screens.cards)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(Strings.Cards.addCard, systemImage: "plus") { editorMode = .add }
            }
        }
        .sheet(item: $editorMode) { mode in
            CardEditor(mode: mode)
        }
        .sheet(item: $mergeSource) { card in
            CardMergeView(source: card)
        }
        .errorAlert(Strings.Cards.couldntChange, message: $errorMessage)
    }

    private func row(_ card: Card) -> some View {
        NavigationLink {
            CardTransactionsView(card: card)
        } label: {
            CardRow(card: card)
        }
        .contextMenu {
            Button(Strings.Common.edit, systemImage: "pencil") { editorMode = .edit(card) }
            if card.isArchived {
                Button(Strings.Common.unarchive, systemImage: "tray.and.arrow.up") { perform { try card.unarchive() } }
            } else {
                Button(Strings.Common.archive, systemImage: "archivebox") { perform { try card.archive() } }
            }
            Button(Strings.Cards.mergeIntoAnother, systemImage: "arrow.triangle.merge") { mergeSource = card }
        }
    }

    /// Runs a change, or shows why it was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Log.store.failed("Changing a card", error)
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CardListView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
