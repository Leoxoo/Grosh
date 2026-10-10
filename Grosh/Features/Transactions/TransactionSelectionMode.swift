import SwiftData
import SwiftUI

extension View {
    /// Choosing transactions in a list to delete them. While `isSelecting`, the title counts the `chosen` ones and the
    /// toolbar offers Done and Delete, which asks how to delete them (``TransactionDeletePrompt``); otherwise the title
    /// is `title`. Make the list select into `chosen` while `isSelecting`.
    func transactionSelectionMode(
        isSelecting: Binding<Bool>, chosen: Binding<Set<Transaction>>, title: String
    ) -> some View {
        modifier(TransactionSelectionMode(isSelecting: isSelecting, chosen: chosen, title: title))
    }
}

private struct TransactionSelectionMode: ViewModifier {
    @Binding var isSelecting: Bool
    @Binding var chosen: Set<Transaction>
    let title: String

    @Environment(\.modelContext) private var context
    @State private var deletePrompt: TransactionDeletePrompt?
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .navigationTitle(isSelecting ? selectionTitle : title)
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { stopSelecting() }
                    }
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", systemImage: "trash", role: .destructive) { confirmDeletingChosen() }
                            .disabled(chosen.isEmpty)
                    }
                }
            }
            .transactionDeleteDialog($deletePrompt, didDelete: stopSelecting)
            .errorAlert("Couldn't Delete Transactions", message: $errorMessage)
    }

    private var selectionTitle: String {
        chosen.isEmpty ? String(localized: "Select Transactions") : String(localized: "\(chosen.count) Selected")
    }

    private func stopSelecting() {
        isSelecting = false
        chosen = []
    }

    private func confirmDeletingChosen() {
        do {
            deletePrompt = try TransactionDeletePrompt(for: Array(chosen).inListOrder(), in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
