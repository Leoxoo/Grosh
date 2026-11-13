import Foundation

/// The editable fields of a category, as the Add/Edit form holds them before ``CategoryCatalog`` checks and saves them.
nonisolated struct CategoryDraft {
    var name: String
    /// Expense or Income. Switching it drops the parent, which can't hold a category of the other type.
    var type: CategoryType {
        didSet {
            if type != oldValue {
                parent = nil
            }
        }
    }
    var symbolName: String
    var color: PaletteColor
    /// The parent category, or `nil` for a top-level category.
    var parent: Category?
    /// The Kind the category sets for its Recurring transactions, or `nil` to follow its parent's.
    var ownKind: RecurringKind?

    init(
        name: String = "",
        type: CategoryType = .expense,
        symbolName: String = Category.placeholderSymbolName,
        color: PaletteColor = .gray,
        parent: Category? = nil,
        ownKind: RecurringKind? = nil
    ) {
        self.name = name
        self.type = type
        self.symbolName = symbolName
        self.color = color
        self.parent = parent
        self.ownKind = ownKind
    }

    init(_ category: Category) {
        self.init(
            name: category.name,
            type: category.type,
            symbolName: category.symbolName,
            color: category.color,
            parent: category.parent,
            ownKind: category.ownKind
        )
    }

    /// A new category of `type`, as Add starts it: no name yet, and a tag on blue until the user picks an icon and color.
    static func new(_ type: CategoryType) -> CategoryDraft {
        CategoryDraft(type: type, symbolName: "tag.fill", color: .blue)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Checks what the draft can check on its own: a category needs a name. Whether the name is free is checked against
    /// the store when it is saved (``CategoryCatalog``).
    func validate() throws {
        guard !trimmedName.isEmpty else { throw CategoryRuleError.nameRequired }
    }
}

nonisolated extension CategoryDraft: ValidatedDraft {}

nonisolated extension CategoryRuleError: EmptyFieldError {
    var isEmptyField: Bool { self == .nameRequired }
}
