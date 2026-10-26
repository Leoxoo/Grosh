import SwiftData
import SwiftUI

/// Picks a category. A transaction's category is picked from the categories of its type the user may pick by hand
/// (``CategoryCatalog/pickerCategories(of:)``): hidden ones and those the app files itself are left out, and Debt/Loan
/// offers only Loan and Debt; the current selection still shows when it isn't offered any more. A filter picks from
/// every category of every type, hidden and locked ones included, or none. The list it opens puts the categories used
/// most in the last month first, each with its subcategories in their usual order, and can be searched by name.
struct CategoryPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Category?
    private let offered: CategoryChoiceList.Offered
    /// The first choice, which picks no category, such as "Any". `nil` offers categories only.
    private let noneTitle: LocalizedStringKey?

    @Environment(\.today) private var today

    /// A transaction's category: those of `type` the user may pick by hand.
    init(title: LocalizedStringKey, type: CategoryType, selection: Binding<Category?>) {
        self.title = title
        _selection = selection
        offered = .pickable(type)
        noneTitle = nil
    }

    /// Any category of any type, hidden and locked ones included, or none (`noneTitle`, such as "Any"): for filters.
    init(title: LocalizedStringKey, everyCategoryOr noneTitle: LocalizedStringKey, selection: Binding<Category?>) {
        self.title = title
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
            LabeledContent(title) {
                if let selection {
                    CategoryLabel(category: selection, indentsSubcategories: false)
                        .foregroundStyle(.primary)
                } else {
                    Text(noneTitle ?? "Choose")
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
        /// Every category, by type.
        case every
    }

    let title: LocalizedStringKey
    let offered: Offered
    let noneTitle: LocalizedStringKey?
    /// The day the categories used most lately are counted back from.
    let today: CalendarDay
    @Binding var selection: Category?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Keeps the list current when categories change.
    @Query private var categories: [Category]
    /// The transactions that decide which categories are used most lately.
    @Query private var recentTransactions: [Transaction]
    @State private var query = ""

    init(
        title: LocalizedStringKey, offered: Offered, noneTitle: LocalizedStringKey?, today: CalendarDay,
        selection: Binding<Category?>
    ) {
        self.title = title
        self.offered = offered
        self.noneTitle = noneTitle
        self.today = today
        _selection = selection
        let firstDay = today.adding(days: -(CategoryCatalog.recentUseDays - 1)).rawValue
        _recentTransactions = Query(filter: #Predicate<Transaction> { $0.dayRaw >= firstDay && $0.deletedAt == nil })
    }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        List {
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
        .searchable(text: $query, prompt: "Search categories")
        .navigationTitle(title)
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
            [ChoiceSection(title: nil, categories: Log.store.attempt("Reading the categories to pick from") {
                try CategoryCatalog(context: context).pickerCategories(of: type)
            } ?? [])]
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
