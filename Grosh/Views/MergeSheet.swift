import SwiftUI

/// The merge flow categories and Cards share: pick what to merge into, tap Merge, confirm. The footer says what
/// will happen. `merge` moves everything and removes the source; a thrown error is shown and nothing closes.
struct MergeSheet<Target: Identifiable & Equatable, Row: View>: View {
    /// The name of what is being merged away.
    let sourceName: String
    /// What it may be merged into, in the order to list them.
    let targets: [Target]
    let targetName: (Target) -> String
    /// What merging into the chosen target (or, before one is chosen, `nil`) does.
    let consequences: (Target?) -> String
    /// Says why there is nothing to merge into, when `targets` is empty.
    let emptyDescription: String
    @ViewBuilder let row: (Target) -> Row
    let merge: (Target) throws -> Void
    /// Called after the merge, once the source no longer exists.
    var onMerged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var target: Target?
    @State private var isConfirming = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(targets) { candidate in
                        Button {
                            target = candidate
                        } label: {
                            HStack {
                                row(candidate)
                                Spacer()
                                if candidate == target {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(candidate == target ? .isSelected : [])
                    }
                } header: {
                    Text("Merge into")
                } footer: {
                    Text(consequences(target))
                }
            }
            .overlay {
                if targets.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Merge Into",
                        systemImage: "arrow.triangle.merge",
                        description: Text(emptyDescription)
                    )
                }
            }
            .navigationTitle("Merge “\(sourceName)”")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { isConfirming = true }
                        .disabled(target == nil)
                }
            }
            .confirmationDialog(
                "Merge “\(sourceName)” into “\(target.map(targetName) ?? "")”?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Merge", role: .destructive, action: performMerge)
            } message: {
                Text("This can't be undone.")
            }
            .errorAlert("Couldn't Merge", message: $errorMessage)
        }
    }

    private func performMerge() {
        guard let target else { return }
        do {
            try merge(target)
            dismiss()
            onMerged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
