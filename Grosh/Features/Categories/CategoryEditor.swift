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
            ? String(localized: Strings.Common.cantBeUndone)
            : String(localized: Strings.Categories.subcategoriesDeletedToo(subcategories))
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
        Log.store.attempt("Reading the parent categories to choose from") {
            try catalog.parentOptions(of: draft.type, for: editing)
        } ?? []
    }

    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                if !isLocked {
                    kindSection
                }
                iconSection
                colorSection
                if let editing, !editing.isLocked {
                    manageSection(for: editing)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editing == nil ? Strings.Categories.addCategory : Strings.Categories.editCategory)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Strings.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? Strings.Common.add : Strings.Common.save, action: save)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isMerging) {
                if let editing {
                    CategoryMergeView(source: editing) { dismiss() }
                }
            }
            .confirmationDialog(
                Strings.Common.deleteNamed(editing?.name ?? ""),
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button(Strings.Common.delete, role: .destructive) {
                    perform {
                        if let editing { try catalog.delete(editing) }
                    }
                }
            } message: {
                if let editing { Text(Self.deleteMessage(for: editing)) }
            }
            .errorAlert(Strings.Categories.couldntSave, message: $errorMessage)
        }
    }

    private var detailsSection: some View {
        Section {
            HStack(spacing: 12) {
                SymbolCircle(symbolName: draft.symbolName, color: draft.color, size: 40)
                TextField(Strings.Common.name, text: $draft.name)
                    .disabled(isLocked)
            }
            if !isLocked {
                Picker(Strings.Common.type, selection: $draft.type) {
                    Text(CategoryType.expense.title).tag(CategoryType.expense)
                    Text(CategoryType.income.title).tag(CategoryType.income)
                }
                .disabled(!canChangeType)
                .onChange(of: draft.type) {
                    // A parent of the old type can't hold a category of the new one.
                    draft.parent = nil
                }

                Picker(Strings.Categories.parent, selection: $draft.parent) {
                    Text(Strings.Common.none).tag(Category?.none)
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
                Text(Strings.Categories.typeLockedFooter)
            } else if !(editing?.children ?? []).isEmpty {
                Text(Strings.Categories.topLevelFooter)
            }
        }
    }

    private var kindSection: some View {
        Section {
            Picker(Strings.Common.kind, selection: kindChoice) {
                if let parent = draft.parent {
                    Text(Strings.Categories.sameAsParent(parent.name, parent.defaultKind.title)).tag(RecurringKind?.none)
                }
                ForEach(RecurringKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(Optional(kind))
                }
            }
        } footer: {
            Text(Strings.Categories.kindFooter)
        }
    }

    /// The Kind the picker shows. A top-level category with none of its own is Regular; a subcategory with none follows
    /// its parent, which its first choice names.
    private var kindChoice: Binding<RecurringKind?> {
        Binding(
            get: { draft.ownKind ?? (draft.parent == nil ? RecurringKind.regular : nil) },
            set: { draft.ownKind = $0 }
        )
    }

    private var iconSection: some View {
        Section(Strings.Common.icon) {
            SymbolGrid(symbols: Self.symbolChoices, selection: $draft.symbolName, color: draft.color)
        }
    }

    private var colorSection: some View {
        Section(Strings.Common.color) {
            PaletteColorGrid(selection: $draft.color)
        }
    }

    private func manageSection(for category: Category) -> some View {
        let canDelete = catalog.canDelete(category)
        return Section {
            Button(
                category.isHidden ? Strings.Categories.unhideCategory : Strings.Categories.hideCategory,
                systemImage: category.isHidden ? "eye" : "eye.slash"
            ) {
                perform { try catalog.setHidden(category, !category.isHidden) }
            }
            Button(Strings.Categories.mergeIntoAnother, systemImage: "arrow.triangle.merge") {
                isMerging = true
            }
            if canDelete {
                Button(Strings.Categories.deleteCategory, systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
            }
        } footer: {
            Text(canDelete
                ? Strings.Categories.hiddenFooter
                : Strings.Categories.cantDeleteFooter)
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
            Log.store.failed("Changing a category", error)
            errorMessage = error.localizedDescription
        }
    }
}
