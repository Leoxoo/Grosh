import SwiftUI

/// The green + that opens the Add Transaction sheet.
struct AddTransactionButton: View {
    @State private var isAdding = false

    var body: some View {
        Button {
            isAdding = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                #if os(iOS)
                .frame(width: 56, height: 56)
                #endif
        }
        #if os(iOS)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        #endif
        .tint(.green)
        .accessibilityLabel("Add Transaction")
        .sheet(isPresented: $isAdding) {
            TransactionEditor(mode: .add)
        }
    }
}

extension View {
    /// Adds the green + that opens the Add Transaction sheet: floating in the bottom corner on iPhone and iPad,
    /// in the toolbar on Mac. Use it inside the tab's `NavigationStack`.
    func addTransactionButton() -> some View {
        #if os(macOS)
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                AddTransactionButton()
            }
        }
        #else
        overlay(alignment: .bottomTrailing) {
            AddTransactionButton()
                .padding()
        }
        #endif
    }
}
