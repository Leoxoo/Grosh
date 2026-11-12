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

    let mode: Mode

    @Environment(\.modelContext) private var context

    var body: some View {
        MadeOnce {
            switch mode {
            case .add(let type):
                (draft: CategoryDraft.new(type), inUse: Set<PersistentIdentifier>())
            case .edit(let category):
                (draft: CategoryDraft(category), inUse: CategoryCatalog(context: context).inUse([category]))
            }
        } content: { start in
            CategoryForm(mode: mode, startingDraft: start.draft, inUse: start.inUse)
        }
    }
}

/// The form behind ``CategoryEditor``, holding the draft from the moment the sheet opens.
private struct CategoryForm: View {
    let mode: CategoryEditor.Mode
    /// Whether the category being edited (or a subcategory) has transactions, counted in the store once when the sheet
    /// opens rather than each time it draws.
    let inUse: Set<PersistentIdentifier>

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var draft: CategoryDraft
    @State private var isMerging = false
    @State private var isConfirmingDelete = false
    @State private var parentOptions = ParentOptions()
    private var saver = SheetSaver(Strings.Categories.couldntSave)

    init(mode: CategoryEditor.Mode, startingDraft: CategoryDraft, inUse: Set<PersistentIdentifier>) {
        self.mode = mode
        self.inUse = inUse
        _draft = State(initialValue: startingDraft)
    }

    private var catalog: CategoryCatalog { CategoryCatalog(context: context) }

    private var editing: Category? {
        if case .edit(let category) = mode { category } else { nil }
    }

    private var isLocked: Bool { editing?.isLocked == true }

    /// A category's type is fixed once it (or a subcategory) has transactions.
    private var canChangeType: Bool {
        guard let editing else { return true }
        return !editing.isLocked && !inUse.contains(editing.persistentModelID)
    }

    /// The parent categories offered for each type, read from the store the first time the type is shown rather than
    /// on every draw, which is every keystroke in Name. Filling it in doesn't redraw anything, so it is safe while
    /// drawing.
    private final class ParentOptions {
        private var byType: [CategoryType: [Category]] = [:]

        func of(_ type: CategoryType, for editing: Category?, in catalog: CategoryCatalog) -> [Category] {
            if let options = byType[type] { return options }
            let options = Log.store.attempt("Reading the parent categories to choose from") {
                try catalog.parentOptions(of: type, for: editing)
            } ?? []
            byType[type] = options
            return options
        }
    }

    var body: some View {
        let check = draft.check
        NavigationStack {
            Form {
                detailsSection(
                    canChangeType: canChangeType,
                    parentOptions: parentOptions.of(draft.type, for: editing, in: catalog),
                    check: check
                )
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
                        .disabled(!check.passes)
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
                    saver.save("Changing a category") {
                        if let editing { try catalog.delete(editing) }
                    }
                }
            } message: {
                if let editing { Text(editing.deleteMessage) }
            }
            .failureAlert(saver)
        }
    }

    /// The name, type and parent.
    private func detailsSection(canChangeType: Bool, parentOptions: [Category], check: RuleCheck) -> some View {
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
            } else if let problem = check.shownProblem {
                Text(problem.localizedDescription)
                    .foregroundStyle(.invalid)
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
            SymbolGrid(symbols: CategoryEditor.symbolChoices, selection: $draft.symbolName, color: draft.color)
        }
    }

    private var colorSection: some View {
        Section(Strings.Common.color) {
            PaletteColorGrid(selection: $draft.color)
        }
    }

    private func manageSection(for category: Category) -> some View {
        let canDelete = CategoryCatalog.canDelete(category, inUse: inUse)
        return Section {
            Button(
                category.isHidden ? Strings.Categories.unhideCategory : Strings.Categories.hideCategory,
                systemImage: category.isHidden ? "eye" : "eye.slash"
            ) {
                saver.save("Changing a category") { try catalog.setHidden(category, !category.isHidden) }
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
        saver.save("Changing a category") {
            if let editing {
                try catalog.update(editing, to: draft)
            } else {
                try catalog.add(draft)
            }
        }
    }
}
