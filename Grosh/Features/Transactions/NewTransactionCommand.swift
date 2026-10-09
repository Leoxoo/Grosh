import SwiftUI

extension FocusedValues {
    /// Whether the focused window shows the Add Transaction sheet.
    @Entry var isAddingTransaction: Binding<Bool>?
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
    /// Lets File → New Transaction (⌘N) open the Add Transaction sheet over this view. Apply it once, at the root.
    func opensNewTransactionOnCommand() -> some View {
        modifier(NewTransactionCommandTarget())
    }
}

private struct NewTransactionCommandTarget: ViewModifier {
    @State private var isAdding = false

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.isAddingTransaction, $isAdding)
            .sheet(isPresented: $isAdding) {
                TransactionEditor(mode: .add)
            }
    }
}
