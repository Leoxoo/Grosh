import SwiftUI

/// A grid of SF Symbols on circles, for picking a wallet's or category's icon. The selected symbol shows in
/// `color`. A selection that isn't one of `symbols` (such as a seeded category's icon) is offered first, so it
/// stays visible and selectable.
struct SymbolGrid: View {
    let symbols: [String]
    @Binding var selection: String
    let color: PaletteColor

    private var choices: [String] {
        symbols.contains(selection) ? symbols : [selection] + symbols
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
            ForEach(choices, id: \.self) { symbol in
                Button {
                    selection = symbol
                } label: {
                    SymbolCircle(symbolName: symbol, color: symbol == selection ? color : .gray, size: 36)
                        .opacity(symbol == selection ? 1 : 0.5)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(symbol == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
