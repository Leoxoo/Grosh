import SwiftData
import SwiftUI

/// Account → Categories: the Expense, Income and Debt/Loan trees. Tap to edit; swipe or right-click to hide,
/// merge or delete. Edit reorders the Expense or Income categories, and each parent's subcategories within it.
struct CategoryListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allCategories: [Category]
    @State private var type: CategoryType = .expense
    @State private var showsHidden = false
    @State private var editorMode: CategoryEditor.Mode?
    @State private var merging: Category?
    @State private var deleting: Category?
    @State private var errorMessage: String?
    /// Whether the list shows the categories for dragging into a new order.
    @State private var isReordering = false

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    private var rows: [Category] {
        CategoryCatalog.tree(of: type, from: allCategories, includingHidden: showsHidden)
    }

    var body: some View {
        List {
            Section {
                Picker(Strings.Common.type, selection: $type) {
                    ForEach(CategoryType.segments, id: \.self) { segment in
                        Text(segment.title).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if isReordering {
                reorderSections
            } else {
                categorySections
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        #endif
        .navigationTitle(Strings.Screens.categories)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if type.isUserManaged {
                    Button(isReordering ? Strings.Common.done : Strings.Common.edit) {
                        withAnimation { isReordering.toggle() }
                    }
                }
                Button(Strings.Categories.addCategory, systemImage: "plus") { editorMode = .add(type) }
                    .disabled(!type.isUserManaged || isReordering)
            }
        }
        .onChange(of: type) {
            // Debt/Loan categories are fixed, so there is nothing of theirs to reorder.
            if !type.isUserManaged {
                isReordering = false
            }
        }
        .sheet(item: $editorMode) { mode in
            CategoryEditor(mode: mode)
        }
        .sheet(item: $merging) { source in
            CategoryMergeView(source: source)
        }
        .confirmationDialog(
            Strings.Common.deleteNamed(deleting?.name ?? ""),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { category in
            Button(Strings.Common.delete, role: .destructive) {
                perform { try catalog.delete(category) }
            }
        } message: { category in
            Text(CategoryEditor.deleteMessage(for: category))
        }
        .errorAlert(Strings.Categories.couldntChange, message: $errorMessage)
    }

    /// The type's tree to tap and swipe, the switch for hidden categories, and the app's own categories.
    @ViewBuilder
    private var categorySections: some View {
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
                    Button(Strings.Common.edit, systemImage: "pencil") { editorMode = .edit(category) }
                    actions(for: category)
                }
            }
        } footer: {
            if type == .debtLoan {
                Text(Strings.Categories.debtLoanFooter)
            }
        }

        Section {
            Toggle(Strings.Categories.showHidden, isOn: $showsHidden)
        } footer: {
            Text(Strings.Categories.hiddenFooter)
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
                    Button(Strings.Common.edit, systemImage: "pencil") { editorMode = .edit(category) }
                }
            }
        } header: {
            Text(Strings.Categories.appsOwn)
        } footer: {
            Text(Strings.Categories.appsOwnFooter)
        }
    }

    /// The type's categories to drag into a new order: the top-level ones first, then each parent's subcategories in a
    /// section of their own, so a subcategory only moves within its parent. Hidden ones are listed too, so every
    /// category keeps its place.
    @ViewBuilder
    private var reorderSections: some View {
        let parents = CategoryCatalog.parents(of: type, from: allCategories)
        Section {
            ForEach(parents) { row(for: $0) }
                .onMove { source, destination in
                    perform { try catalog.move(parents, fromOffsets: source, toOffset: destination) }
                }
        } header: {
            Text(Strings.Screens.categories)
        } footer: {
            Text(Strings.Categories.reorderFooter)
        }
        ForEach(parents.filter { !($0.children ?? []).isEmpty }) { parent in
            let subcategories = CategoryCatalog.subcategories(of: parent)
            Section(parent.name) {
                ForEach(subcategories) { row(for: $0, indented: false) }
                    .onMove { source, destination in
                        perform { try catalog.move(subcategories, fromOffsets: source, toOffset: destination) }
                    }
            }
        }
    }

    private func row(for category: Category, indented: Bool = true) -> some View {
        HStack {
            CategoryLabel(category: category, indentsSubcategories: indented)
            Spacer()
            if category.isHidden {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Strings.Common.hidden)
            }
            if category.isLocked {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Strings.Categories.locked)
            }
        }
        .opacity(category.isHiddenInTree ? 0.5 : 1)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func actions(for category: Category) -> some View {
        if !category.isLocked {
            if catalog.canDelete(category) {
                Button(Strings.Common.delete, systemImage: "trash", role: .destructive) { deleting = category }
            }
            Button(Strings.Common.merge, systemImage: "arrow.triangle.merge") { merging = category }
                .tint(.mergeAction)
            Button(
                category.isHidden ? Strings.Common.unhide : Strings.Common.hide,
                systemImage: category.isHidden ? "eye" : "eye.slash"
            ) {
                perform { try catalog.setHidden(category, !category.isHidden) }
            }
            .tint(.hideAction)
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Log.store.failed("Changing a category", error)
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
