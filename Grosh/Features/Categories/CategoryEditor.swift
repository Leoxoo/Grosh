import SwiftData
import SwiftUI

/// Adds a category or edits one: name, icon on a colored circle, type and parent. Editing also offers hide,
/// merge and delete. A locked category only takes a new icon.
struct CategoryEditor: View {
    enum Mode: Identifiable {
        /// Adds a category of this type.
        case add(CategoryType)
        case edit(Category)

        var id: AnyHashable {
            switch self {
            case .add(let type): "add-\(type.rawValue)"
            case .edit(let category): category.persistentModelID
            }
        }
    }

    static let symbolChoices = [
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
        "bag.fill", "tshirt.fill", "house.fill", "bolt.fill",
        "drop.fill", "flame.fill", "wifi", "iphone",
        "car.fill", "bus.fill", "tram.fill", "fuelpump.fill",
        "airplane", "bicycle", "heart.fill", "cross.case.fill",
        "pills.fill", "stethoscope", "figure.run", "graduationcap.fill",
        "book.fill", "gamecontroller.fill", "film.fill", "music.note",
        "gift.fill", "pawprint.fill", "stroller.fill", "sparkles",
        "hammer.fill", "wrench.and.screwdriver.fill", "shield.fill", "doc.text.fill",
        "percent", "building.columns.fill", "banknote.fill", "dollarsign.circle.fill",
        "creditcard.fill", "chart.line.uptrend.xyaxis", "briefcase.fill", "trophy.fill",
        "tag.fill", "person.2.fill", "globe.americas.fill", "leaf.fill",
        "star.fill", "questionmark.circle.fill", "ellipsis.circle.fill", "flag.fill",
    ]

    /// What deleting `category` takes with it, for the confirmation.
    static func deleteMessage(for category: Category) -> String {
        let subcategories = category.children?.count ?? 0
        return subcategories == 0
            ? "This can't be undone."
            : "Its \(subcategories) subcategories are deleted too. This can't be undone."
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: CategoryDraft
    @State private var isMerging = false
    @State private var isConfirmingDelete = false
    @State private var errorMessage: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add(let type):
            _draft = State(initialValue: CategoryDraft(type: type, symbolName: "tag.fill", color: .blue))
        case .edit(let category):
            _draft = State(initialValue: CategoryDraft(category))
        }
    }

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    private var editing: Category? {
        if case .edit(let category) = mode { category } else { nil }
    }

    private var isLocked: Bool { editing?.isLocked == true }

    /// A category's type is fixed once it (or a subcategory) has transactions.
    private var canChangeType: Bool {
        guard let editing else { return true }
        return !editing.isLocked && !catalog.hasTransactions(editing)
    }

    private var parentOptions: [Category] {
        (try? catalog.parentOptions(of: draft.type, for: editing)) ?? []
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                iconSection
                colorSection
                if let editing, !editing.isLocked {
                    manageSection(for: editing)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? "Add Category" : "Edit Category")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isMerging) {
                if let editing {
                    CategoryMergeView(source: editing) { dismiss() }
                }
            }
            .confirmationDialog(
                "Delete “\(editing?.name ?? "")”?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    perform {
                        if let editing { try catalog.delete(editing) }
                    }
                }
            } message: {
                if let editing { Text(Self.deleteMessage(for: editing)) }
            }
            .errorAlert("Couldn't Save Category", message: $errorMessage)
        }
    }

    private var detailsSection: some View {
        Section {
            HStack(spacing: 12) {
                SymbolCircle(symbolName: draft.symbolName, color: draft.color, size: 40)
                TextField("Name", text: $draft.name)
                    .disabled(isLocked)
            }
            if !isLocked {
                Picker("Type", selection: $draft.type) {
                    Text(CategoryType.expense.title).tag(CategoryType.expense)
                    Text(CategoryType.income.title).tag(CategoryType.income)
                }
                .disabled(!canChangeType)
                .onChange(of: draft.type) {
                    // A parent of the old type can't hold a category of the new one.
                    draft.parent = nil
                }

                Picker("Parent", selection: $draft.parent) {
                    Text("None").tag(Category?.none)
                    ForEach(parentOptions) { parent in
                        Text(parent.name).tag(Category?.some(parent))
                    }
                }
                .disabled(parentOptions.isEmpty)
            }
        } footer: {
            if isLocked {
                Text(CategoryRuleError.locked.localizedDescription)
            } else if !canChangeType {
                Text("This category has transactions, so its type can't change.")
            } else if !(editing?.children ?? []).isEmpty {
                Text("A category with subcategories stays at the top level.")
            }
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            SymbolGrid(symbols: Self.symbolChoices, selection: $draft.symbolName, color: draft.color)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            PaletteColorGrid(selection: $draft.color)
        }
    }

    private func manageSection(for category: Category) -> some View {
        let canDelete = catalog.canDelete(category)
        return Section {
            Button(
                category.isHidden ? "Unhide Category" : "Hide Category",
                systemImage: category.isHidden ? "eye" : "eye.slash"
            ) {
                perform { try catalog.setHidden(category, !category.isHidden) }
            }
            Button("Merge into Another Category…", systemImage: "arrow.triangle.merge") {
                isMerging = true
            }
            if canDelete {
                Button("Delete Category", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            Text(canDelete
                ? "Hidden categories leave the picker but stay on their transactions."
                : "This category has transactions, so it can't be deleted. Merge it into another category instead.")
        }
    }

    private func save() {
        perform {
            if let editing {
                try catalog.update(editing, to: draft)
            } else {
                try catalog.add(draft)
            }
        }
    }

    /// Runs a change and closes the sheet, or shows why the change was refused.
    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
