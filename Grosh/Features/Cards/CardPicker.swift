import SwiftData
import SwiftUI

/// Picks the Card a transaction was paid with. It offers only the unarchived Cards whose paying wallet is
/// `wallet`, in the order they were added, plus "None". The current selection stays visible even when it
/// was archived since (editing a past transaction). Clear the selection when the transaction's wallet changes.
struct CardPicker: View {
    let title: LocalizedStringKey
    let wallet: Wallet?
    @Binding var selection: Card?

    var body: some View {
        Picker(title, selection: $selection) {
            Text("None").tag(Card?.none)
            ForEach(Card.pickerChoices(for: wallet, keeping: selection)) { card in
                Label {
                    Text(card.displayName)
                } icon: {
                    Image(systemName: Card.symbolName)
                        .foregroundStyle(card.color.color)
                }
                .tag(Optional(card))
            }
        }
    }
}
