import SwiftData
import SwiftUI

/// Picks a category. A transaction's category is picked from the categories of its type the user may pick by hand
/// (``CategoryCatalog/pickable(of:from:)``): hidden ones and those the app files itself are left out, and Debt/Loan
/// offers only Loan and Debt; the current selection still shows when it isn't offered any more. Passing `types` puts
/// Expense, Income and Debt/Loan at the top of that list, and choosing one changes the transaction's type. A filter
/// picks from every category of every type, hidden and locked ones included, or none. The list it opens puts the
/// categories used most in the last month first, each with its subcategories in their usual order, and can be searched
/// by name. Where a category of the user's own can be added, New category is the first row.
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

    /// A transaction's category, with Expense, Income and Debt/Loan chosen in the list. `types` is the ones it offers.
    init(
        title: LocalizedStringResource, type: Binding<CategoryType>, types: [CategoryType],
        selection: Binding<Category?>, systemImage: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        _selection = selection
        offered = .switching(type, types)
        noneTitle = nil
    }

    /// Any category of any type, hidden and locked ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(
        title: LocalizedStringResource, everyCategoryOr noneTitle: LocalizedStringResource,
        selection: Binding<Category?>, systemImage: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        _selection = selection
        offered = .every
        self.noneTitle = noneTitle
    }

    var body: some View {
        NavigationLink {
            CategoryChoiceList(
                title: title, offered: offered, noneTitle: noneTitle, today: today, selection: $selection
            )
        } label: {
            FormFieldRow(title: title, systemImage: systemImage) {
                Group {
                    if let selection {
                        CategoryLabel(category: selection, indentsSubcategories: false)
                            .foregroundStyle(.primary)
                    } else {
                        Text(noneTitle ?? Strings.Common.choose)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// The list ``CategoryPicker`` pushes: the offered categories, the parents used most lately first
/// (``CategoryCatalog/byRecentUse(_:transactions:today:)``), each followed by its subcategories in their usual order,
/// indented. A search narrows it to the categories whose names match.
private struct CategoryChoiceList: View {
    enum Offered {
        /// The categories of a type the user may pick by hand.
        case pickable(CategoryType)
        /// Expense, Income and Debt/Loan, whichever of `types` this transaction offers, written back as it changes.
        case switching(Binding<CategoryType>, [CategoryType])
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
        case .switching(let type, _): type.wrappedValue.isUserManaged ? type.wrappedValue : nil
        case .every: .expense
        }
    }

    var body: some View {
        let sections = self.sections
        List {
            if case .switching(let type, let types) = offered, types.count > 1 {
                Section {
                    Picker(Strings.Common.type, selection: type) {
                        ForEach(types, id: \.self) { segment in
                            Text(segment.title).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            if let addableType {
                Section {
                    Button(Strings.Categories.newCategory, systemImage: "plus.circle") {
                        adding = NewCategory(type: addableType)
                    }
                }
            }
            if noneTitle != nil && !isSearching {
                Section {
                    row(nil)
                }
            }
            ForEach(sections) { section in
                Section {
                    ForEach(section.categories) { row($0) }
                } header: {
                    if let title = section.title {
                        Text(title)
                    }
                }
            }
        }
        .overlay {
            if isSearching && sections.isEmpty {
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

    /// Chooses the category the editor just added, and closes the list. A transaction's type follows it.
    private func finishAdding() {
        guard let created else { return }
        self.created = nil
        switch offered {
        case .switching(let type, let types):
            guard types.contains(created.type) else { return }
            if created.type != type.wrappedValue {
                type.wrappedValue = created.type
            }
        case .pickable(let type):
            guard created.type == type else { return }
        case .every:
            break
        }
        selection = created
        dismiss()
    }

    /// One section of choices: under its type's name when every category is offered.
    private struct ChoiceSection: Identifiable {
        let title: String?
        let categories: [Category]
        var id: String { title ?? "" }
    }

    private var sections: [ChoiceSection] {
        let all: [ChoiceSection] = switch offered {
        case .pickable(let type):
            [ChoiceSection(title: nil, categories: CategoryCatalog.pickable(of: type, from: categories))]
        case .switching(let type, _):
            [ChoiceSection(title: nil, categories: CategoryCatalog.pickable(of: type.wrappedValue, from: categories))]
        case .every:
            CategoryType.allCases.map { type in
                ChoiceSection(title: type.title, categories: CategoryCatalog.tree(of: type, from: categories))
            }
        }
        return all
            .map { ChoiceSection(title: $0.title, categories: arranged($0.categories)) }
            .filter { !$0.categories.isEmpty }
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
