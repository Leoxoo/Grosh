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
                .accessibilityLabel(choice.rawValue.capitalized)
                .accessibilityAddTraits(choice == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
