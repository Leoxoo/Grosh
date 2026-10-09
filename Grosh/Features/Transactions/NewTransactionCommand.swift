import SwiftUI

extension FocusedValues {
    /// Whether the focused window shows the Add Transaction sheet.
    @Entry var isAddingTransaction: Binding<Bool>?
}

extension EnvironmentValues {
    /// Whether the window shows the Add Transaction sheet. The green + sets it; `nil` outside
    /// ``SwiftUI/View/presentsAddTransaction()``.
    @Entry var isAddingTransaction: Binding<Bool>? = nil
}

/// File → New Transaction (⌘N), in place of New Window.
struct NewTransactionCommands: Commands {
    @FocusedBinding(\.isAddingTransaction) private var isAddingTransaction

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Transaction") { isAddingTransaction = true }
                .keyboardShortcut("n")
                .disabled(isAddingTransaction == nil)
        }
    }
}

extension View {
    /// The one place the Add Transaction sheet is presented from: every green + and File → New Transaction (⌘N)
    /// open it here. Apply it once, at the root.
    func presentsAddTransaction() -> some View {
        modifier(AddTransactionPresenter())
    }
}

private struct AddTransactionPresenter: ViewModifier {
    @State private var isAdding = false

    func body(content: Content) -> some View {
        content
            .environment(\.isAddingTransaction, $isAdding)
            .focusedSceneValue(\.isAddingTransaction, $isAdding)
            .sheet(isPresented: $isAdding) {
                TransactionEditor(mode: .add)
            }
    }
}
