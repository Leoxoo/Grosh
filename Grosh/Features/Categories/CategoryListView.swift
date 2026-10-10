import SwiftData
import SwiftUI

/// Account → Categories: the Expense, Income and Debt/Loan trees. Tap to edit; swipe or right-click to hide,
/// merge or delete.
struct CategoryListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allCategories: [Category]
    @State private var type: CategoryType = .expense
    @State private var showsHidden = false
    @State private var editorMode: CategoryEditor.Mode?
    @State private var merging: Category?
    @State private var deleting: Category?
    @State private var errorMessage: String?

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    private var rows: [Category] {
        CategoryCatalog.tree(of: type, from: allCategories, includingHidden: showsHidden)
    }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $type) {
                    ForEach(CategoryType.segments, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section {
                ForEach(rows) { category in
                    Button {
                        editorMode = .edit(category)
                    } label: {
                        row(for: category)
                    }
                    .buttonStyle(.plain)
                    .swipeActions { actions(for: category) }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(category) }
                        actions(for: category)
                    }
                }
            } footer: {
                if type == .debtLoan {
                    Text("Debt/Loan categories are fixed. You can change their icons.")
                }
            }

            Section {
                Toggle("Show hidden categories", isOn: $showsHidden)
            } footer: {
                Text("Hidden categories leave the picker but stay on their transactions.")
            }

            Section {
                ForEach(CategoryCatalog.tree(of: .system, from: allCategories)) { category in
                    Button {
                        editorMode = .edit(category)
                    } label: {
                        row(for: category)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editorMode = .edit(category) }
                    }
                }
            } header: {
                Text("The app's own categories")
            } footer: {
                Text("The app files transactions under these itself, such as a new wallet's Starting balance. You can change their icons.")
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Category", systemImage: "plus") { editorMode = .add(type) }
                    .disabled(!type.isUserManaged)
            }
        }
        .sheet(item: $editorMode) { mode in
            CategoryEditor(mode: mode)
        }
        .sheet(item: $merging) { source in
            CategoryMergeView(source: source)
        }
        .confirmationDialog(
            "Delete “\(deleting?.name ?? "")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { category in
            Button("Delete", role: .destructive) {
                perform { try catalog.delete(category) }
            }
        } message: { category in
            Text(CategoryEditor.deleteMessage(for: category))
        }
        .errorAlert("Couldn't Change Category", message: $errorMessage)
    }

    private func row(for category: Category) -> some View {
        HStack {
            CategoryLabel(category: category)
            Spacer()
            if category.isHidden {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hidden")
            }
            if category.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked")
            }
        }
        .opacity(category.isHiddenInTree ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actions(for category: Category) -> some View {
        if !category.isLocked {
            if catalog.canDelete(category) {
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = category }
            }
            Button("Merge", systemImage: "arrow.triangle.merge") { merging = category }
                .tint(.indigo)
            Button(
                category.isHidden ? "Unhide" : "Hide",
                systemImage: category.isHidden ? "eye" : "eye.slash"
            ) {
                perform { try catalog.setHidden(category, !category.isHidden) }
            }
            .tint(.gray)
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        CategoryListView()
    }
    .modelContainer(try! GroshStore.makeSeededContainer(inMemory: true))
}
