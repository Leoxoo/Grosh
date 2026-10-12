import SwiftUI

/// The green + that opens the Add Transaction sheet, which ``SwiftUI/View/presentsAddTransaction()`` presents.
struct AddTransactionButton: View {
    @Environment(\.isAddingTransaction) private var isAdding

    var body: some View {
        Button {
            isAdding?.wrappedValue = true
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(.green)
        .accessibilityLabel("Add Transaction")
        .disabled(isAdding == nil)
    }
}

extension View {
    /// Adds the green + that opens the Add Transaction sheet, floating in the bottom corner. Use it inside the tab's
    /// `NavigationStack`. On Mac the list also gets bottom room, so the button never covers its last row.
    func addTransactionButton() -> some View {
        overlay(alignment: .bottomTrailing) {
            AddTransactionButton()
                .padding()
        }
        #if os(macOS)
        // The 56pt circle, its 16pt padding, and a 16pt gap above the last row.
        .contentMargins(.bottom, 88, for: .scrollContent)
        #endif
    }
}
