import SwiftData
import SwiftUI

/// Account → Cards: every Card in the order it was added. Tap to edit, swipe to archive.
struct CardListView: View {
    @Query(filter: #Predicate<Card> { !$0.isArchived }, sort: Card.userOrder) private var cards: [Card]
    @Query(filter: #Predicate<Card> { $0.isArchived }, sort: Card.userOrder) private var archivedCards: [Card]
    @State private var editorMode: EditorMode<Card>?
    @State private var mergeSource: Card?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(cards) { card in
                    row(card)
                        .swipeActions {
                            Button("Archive", systemImage: "archivebox") { perform { try card.archive() } }
                                .tint(.orange)
                        }
                }
            } footer: {
                if !cards.isEmpty {
                    Text("A Card is only a label for what an expense was paid with. It never changes any balance.")
                }
            }

            if !archivedCards.isEmpty {
                Section {
                    ForEach(archivedCards) { card in
                        row(card)
                            .foregroundStyle(.secondary)
                            .swipeActions {
                                Button("Unarchive", systemImage: "tray.and.arrow.up") { perform { try card.unarchive() } }
                                    .tint(.green)
                            }
                    }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived Cards leave the pickers but stay on their transactions.")
                }
            }
        }
        .overlay {
            if cards.isEmpty && archivedCards.isEmpty {
                ContentUnavailableView {
                    Label("No Cards", systemImage: "creditcard")
                } description: {
                    Text("Add the cards you pay with to see which one each expense went on.")
                } actions: {
                    Button("Add Card") { editorMode = .add }
                }
            }
        }
        .navigationTitle("Cards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Card", systemImage: "plus") { editorMode = .add }
            }
        }
        .sheet(item: $editorMode) { mode in
            CardEditor(mode: mode)
        }
        .sheet(item: $mergeSource) { card in
            CardMergeView(source: card)
        }
        .errorAlert("Couldn't Change Card", message: $errorMessage)
    }

    private func row(_ card: Card) -> some View {
        Button {
            editorMode = .edit(card)
        } label: {
            CardRow(card: card)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "pencil") { editorMode = .edit(card) }
            if card.isArchived {
                Button("Unarchive", systemImage: "tray.and.arrow.up") { perform { try card.unarchive() } }
            } else {
                Button("Archive", systemImage: "archivebox") { perform { try card.archive() } }
            }
            Button("Merge into Another Card…", systemImage: "arrow.triangle.merge") { mergeSource = card }
        }
    }

    /// Runs a change, or shows why it was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CardListView()
    }
    .modelContainer(try! GroshStore.makeContainer(inMemory: true))
}
