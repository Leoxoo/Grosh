import SwiftUI

/// Add Card: a search of the rewards catalog with Custom card first. Picking a catalog card opens the Card form with
/// its name filled in and the Card linked to it; Custom card opens the form as it is.
struct AddCardSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// The draft the form starts as, once the user picked an entry or Custom card.
    @State private var picked: CardDraft?

    var body: some View {
        if let picked {
            CardEditor(mode: .add, newDraft: picked)
        } else {
            NavigationStack {
                CatalogCardSearch(offersCustomCard: true) { entry in
                    picked = entry.map(CardDraft.new(from:)) ?? .new
                }
                .navigationTitle(Strings.Cards.addCard)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Strings.Common.cancel) { dismiss() }
                    }
                }
            }
        }
    }
}
