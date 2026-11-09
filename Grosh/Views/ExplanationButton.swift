import SwiftUI

/// The ⓘ beside a Report card's title that shows, in a popover, what the card counts.
struct ExplanationButton: View {
    let label: LocalizedStringResource
    let explanation: String

    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .popover(isPresented: $isShowing) {
            Text(explanation)
                .font(.subheadline)
                .padding()
                .frame(maxWidth: 320, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
}
