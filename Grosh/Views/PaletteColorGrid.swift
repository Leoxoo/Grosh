import SwiftUI

/// The palette as a grid of color swatches, for picking a wallet's, category's or Card's color.
struct PaletteColorGrid: View {
    @Binding var selection: PaletteColor

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 32), spacing: 12)], spacing: 12) {
            ForEach(PaletteColor.allCases, id: \.self) { choice in
                Button {
                    selection = choice
                } label: {
                    Circle()
                        .fill(choice.color.gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if choice == selection {
                                Image(systemName: "checkmark")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(choice.name))
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

extension PaletteColor {
    /// The color's name, as VoiceOver reads it.
    var name: LocalizedStringResource {
        switch self {
        case .red: Strings.Palette.red
        case .orange: Strings.Palette.orange
        case .yellow: Strings.Palette.yellow
        case .green: Strings.Palette.green
        case .mint: Strings.Palette.mint
        case .teal: Strings.Palette.teal
        case .cyan: Strings.Palette.cyan
        case .blue: Strings.Palette.blue
        case .indigo: Strings.Palette.indigo
        case .purple: Strings.Palette.purple
        case .pink: Strings.Palette.pink
        case .brown: Strings.Palette.brown
        case .gray: Strings.Palette.gray
        }
    }
}
