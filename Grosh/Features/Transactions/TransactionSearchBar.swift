import SwiftUI

/// The search field the Transactions tab's Search button opens above its header. It finds a note, a category or an
/// amount across all time and every wallet, as the Search tab does. Cancel closes it, and the search text with it.
struct TransactionSearchBar: View {
    @Binding var text: String
    /// Closes the field.
    let close: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Note, category or amount", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: close)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .onAppear { isFocused = true }
    }
}
