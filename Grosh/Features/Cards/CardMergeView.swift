import SwiftData
import SwiftUI

/// Merges one Card into another: every transaction paid with `source` moves to the chosen Card, then `source` is removed.
struct CardMergeView: View {
    let source: Card
    /// Called after the merge, once `source` no longer exists.
    var onMerged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var target: Card?
    @State private var errorMessage: String?

    private var targets: [Card] { source.mergeTargets }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(targets) { card in
                        Button {
                            target = card
                        } label: {
                            CardRow(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Merge “\(source.name)” into")
                } footer: {
                    Text("Its transactions move to the Card you choose, and “\(source.name)” is removed.")
                }
            }
            .overlay {
                if targets.isEmpty {
                    ContentUnavailableView(
                        "No Other Cards",
                        systemImage: "creditcard",
                        description: Text("A Card merges into another unarchived Card paid from the same wallet.")
                    )
                }
            }
            .navigationTitle("Merge Card")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Merge “\(source.name)” into “\(target?.name ?? "")”?",
                isPresented: Binding(get: { target != nil }, set: { if !$0 { target = nil } }),
                titleVisibility: .visible,
                presenting: target
            ) { target in
                Button("Merge", role: .destructive) { merge(into: target) }
            } message: { target in
                Text("\(source.transactions?.count ?? 0) transactions move to “\(target.name)”. This can't be undone.")
            }
            .errorAlert("Couldn't Merge Cards", message: $errorMessage)
        }
    }

    private func merge(into target: Card) {
        do {
            try source.merge(into: target, in: context)
            try context.save()
            dismiss()
            onMerged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
