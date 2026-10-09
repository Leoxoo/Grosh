import SwiftUI

extension PaletteColor {
    /// The system color this palette entry stands for, so it follows light and dark mode.
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

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
