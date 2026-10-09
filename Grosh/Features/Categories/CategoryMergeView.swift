import SwiftData
import SwiftUI

/// Picks the category to merge `source` into, then moves its transactions (and subcategories) there and removes it.
struct CategoryMergeView: View {
    let source: Category
    /// Called after the merge, once `source` no longer exists.
    var onMerged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var target: Category?
    @State private var isConfirming = false
    @State private var errorMessage: String?

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    private var targets: [Category] { (try? catalog.mergeTargets(for: source)) ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(targets) { candidate in
                        Button {
                            target = candidate
                        } label: {
                            HStack {
                                CategoryLabel(category: candidate)
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
                    Text(consequences(into: target))
                }
            }
            .overlay {
                if targets.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Merge Into",
                        systemImage: "arrow.triangle.merge",
                        description: Text("There's no other \(source.type.title) category this one can be merged into.")
                    )
                }
            }
            .navigationTitle("Merge “\(source.name)”")
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
                "Merge “\(source.name)” into “\(target?.name ?? "")”?",
                isPresented: $isConfirming,
                titleVisibility: .visible
            ) {
                Button("Merge", role: .destructive, action: merge)
            } message: {
                Text("This can't be undone.")
            }
            .errorAlert("Couldn't Merge", message: $errorMessage)
        }
    }

    private func consequences(into target: Category?) -> String {
        let destination = target.map { "“\($0.name)”" } ?? "the category you pick"
        let transactions = source.transactions?.count ?? 0
        let subcategories = source.children?.count ?? 0
        var text = transactions == 1
            ? "Its transaction moves to \(destination)"
            : "Its \(transactions) transactions move to \(destination)"
        if subcategories > 0 {
            text += " and its \(subcategories) subcategories move under it"
        }
        return text + ". Then “\(source.name)” is removed."
    }

    private func merge() {
        do {
            guard let target else { return }
            try catalog.merge(source, into: target)
            dismiss()
            onMerged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
