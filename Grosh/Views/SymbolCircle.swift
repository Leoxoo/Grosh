import SwiftUI

/// An SF Symbol on a colored circle: how wallets, categories and Cards are drawn.
struct SymbolCircle: View {
    let symbolName: String
    let color: PaletteColor
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.color.gradient, in: Circle())
            .accessibilityHidden(true)
    }
}
