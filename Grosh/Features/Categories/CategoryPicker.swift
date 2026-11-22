import SwiftData
import SwiftUI

/// Picks a category. A transaction's category is picked from the categories of its type the user may pick by hand
/// (``CategoryCatalog/pickable(of:from:)``): hidden ones and those the app files itself are left out, and Debt/Loan
/// offers only Loan and Debt; the current selection still shows when it isn't offered any more. A filter picks from
/// every category of every type, hidden and locked ones included, or none. The list it opens puts the categories used
/// most in the last month first, each with its subcategories in their usual order, and can be searched by name. Where
/// a category of the user's own can be added, New category is the first row.
struct CategoryPicker: View {
    let title: LocalizedStringResource
    var systemImage: String?
    @Binding var selection: Category?
    private let offered: CategoryChoiceList.Offered
    /// The first choice, which picks no category, such as "Any". `nil` offers categories only.
    private let noneTitle: LocalizedStringResource?

    @Environment(\.today) private var today

    /// A transaction's category: those of `type` the user may pick by hand.
    init(title: LocalizedStringResource, type: CategoryType, selection: Binding<Category?>, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        _selection = selection
        offered = .pickable(type)
        noneTitle = nil
    }

    /// Any category of any type, hidden and locked ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringResource, everyCategoryOr noneTitle: LocalizedStringResource, selection: Binding<Category?>) {
        self.title = title
        _selection = selection
        offered = .every
        self.noneTitle = noneTitle
    }

    /// The compact row's mark: the picked category's icon, or the field's icon while none is picked.
    @ViewBuilder
    private var categoryRowMark: some View {
        if let selection {
            CategoryIcon(category: selection, size: 28)
                .accessibilityLabel(Text(title))
        } else {
            FieldLabel(title: title, systemImage: systemImage)
        }
    }

    @ViewBuilder
    private var categoryRow: some View {
        if systemImage != nil {
            FormFieldRow(compact: true, appliesListChrome: false, leading: categoryRowMark) {
                if let selection {
                    Text(selection.name)
                        .foregroundStyle(.primary)
                } else {
                    Text(noneTitle ?? Strings.Common.chooseCategory)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            FormFieldRow(title: title, systemImage: nil) {
                if let selection {
                    CategoryLabel(category: selection, indentsSubcategories: false)
                        .foregroundStyle(.primary)
                } else {
                    Text(noneTitle ?? Strings.Common.choose)
                }
            }
        }
    }

    var body: some View {
        let link = NavigationLink {
            CategoryChoiceList(title: title, offered: offered, noneTitle: noneTitle, today: today, selection: $selection)
        } label: {
            categoryRow
        }
        if systemImage != nil {
            link
                .buttonStyle(.plain)
                .navigationLinkIndicatorVisibility(.hidden)
                .compactFormRowChrome(true)
        } else {
            link
        }
    }
}

/// The list ``CategoryPicker`` pushes: the offered categories, the parents used most lately first
/// (``CategoryCatalog/byRecentUse(_:transactions:today:)``), each followed by its subcategories in their usual order,
/// indented. Each parent and its subcategories sit in their own group, with a gap before the next parent. A search
/// narrows it to the categories whose names match.
private struct CategoryChoiceList: View {
    enum Offered {
        /// The categories of a type the user may pick by hand.
        case pickable(CategoryType)
        /// Every category, by type.
        case every
    }

    /// The type New category adds, long enough for the editor's sheet to present it.
    private struct NewCategory: Identifiable {
        let type: CategoryType
        var id: String { type.rawValue }
    }

    let title: LocalizedStringResource
    let offered: Offered
    let noneTitle: LocalizedStringResource?
    /// The day the categories used most lately are counted back from.
    let today: CalendarDay
    @Binding var selection: Category?

    @Environment(\.dismiss) private var dismiss
    /// Every category, which the choices are arranged from.
    @Query private var categories: [Category]
    /// The transactions that decide which categories are used most lately.
    @Query private var recentTransactions: [Transaction]
    @State private var query = ""
    @State private var adding: NewCategory?
    /// The category just added, chosen once its editor closes.
    @State private var created: Category?

    init(
        title: LocalizedStringResource, offered: Offered, noneTitle: LocalizedStringResource?, today: CalendarDay,
        selection: Binding<Category?>
    ) {
        self.title = title
        self.offered = offered
        self.noneTitle = noneTitle
        self.today = today
        _selection = selection
        _recentTransactions = Query(CategoryCatalog.recentTransactions(through: today))
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The type New category adds here, or `nil` when this list's categories are fixed.
    private var addableType: CategoryType? {
        switch offered {
        case .pickable(let type): type.isUserManaged ? type : nil
        case .every: .expense
        }
    }

    var body: some View {
        let groups = self.groups
        List {
            if let addableType {
                Section {
                    Button(Strings.Categories.newCategory, systemImage: "plus.circle") {
                        adding = NewCategory(type: addableType)
                    }
                    .groupedRow(.only)
                }
            }
            if noneTitle != nil && !isSearching {
                Section {
                    row(nil)
                        .groupedRow(.only)
                }
            }
            ForEach(groups) { group in
                categorySection(group)
            }
        }
        .roundedSectionsListStyle()
        #if os(iOS)
        .listSectionSpacing(.compact)
        #endif
        .overlay {
            if isSearching && groups.isEmpty {
                ContentUnavailableView.search(text: query.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        .searchable(text: $query, prompt: Strings.Categories.searchCategories)
        .navigationTitle(title)
        .sheet(item: $adding, onDismiss: finishAdding) { adding in
            CategoryEditor(mode: .add(adding.type)) { category in
                created = category
            }
        }
    }

    /// Chooses the category the editor just added, when this list offers its type, and closes the list.
    private func finishAdding() {
        guard let created else { return }
        self.created = nil
        if case .pickable(let type) = offered, created.type != type { return }
        selection = created
        dismiss()
    }

    /// One group of choices: a parent and its subcategories. `title` is the type's name on the first group of that
    /// type, when every category is offered.
    private struct ChoiceGroup: Identifiable {
        let title: String?
        let categories: [Category]
        var id: PersistentIdentifier { categories[0].persistentModelID }
    }

    private var groups: [ChoiceGroup] {
        let offeredTrees: [(title: String?, categories: [Category])] = switch offered {
        case .pickable(let type):
            [(nil, CategoryCatalog.pickable(of: type, from: categories))]
        case .every:
            CategoryType.allCases.map { type in
                (type.title, CategoryCatalog.tree(of: type, from: categories))
            }
        }
        return offeredTrees.flatMap { title, tree in
            CategoryCatalog.parentGroups(in: arranged(tree)).enumerated().map { index, categories in
                ChoiceGroup(title: index == 0 ? title : nil, categories: categories)
            }
        }
    }

    /// A parent and its subcategories on one card. The type's name heads the first card of that type.
    @ViewBuilder
    private func categorySection(_ group: ChoiceGroup) -> some View {
        if let title = group.title {
            Section {
                GroupedForEach(group.categories) { row($0) }
            } header: {
                Text(title)
            }
        } else {
            Section {
                GroupedForEach(group.categories) { row($0) }
            }
        }
    }

    /// `tree` as the list shows it: the most used lately first, narrowed to the categories matching the search.
    private func arranged(_ tree: [Category]) -> [Category] {
        CategoryCatalog.matching(
            query, in: CategoryCatalog.byRecentUse(tree, transactions: recentTransactions, today: today)
        )
    }

    private func row(_ category: Category?) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack {
                if let category {
                    // Search results stand alone, so a subcategory isn't indented under a parent that may not show.
                    CategoryLabel(category: category, indentsSubcategories: !isSearching)
                } else if let noneTitle {
                    Text(noneTitle)
                }
                Spacer()
                if category == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(category == selection ? .isSelected : [])
    }
}
