/// The editable fields of a category, as the Add/Edit form holds them before ``CategoryCatalog`` checks and saves them.
struct CategoryDraft {
    var name: String
    var type: CategoryType
    var symbolName: String
    var color: PaletteColor
    /// The parent category, or `nil` for a top-level category.
    var parent: Category?

    init(
        name: String = "",
        type: CategoryType = .expense,
        symbolName: String = "questionmark",
        color: PaletteColor = .gray,
        parent: Category? = nil
    ) {
        self.name = name
        self.type = type
        self.symbolName = symbolName
        self.color = color
        self.parent = parent
    }

    /// The category's current fields, ready to edit.
    init(_ category: Category) {
        self.init(
            name: category.name,
            type: category.type,
            symbolName: category.symbolName,
            color: category.color,
            parent: category.parent
        )
    }
}
