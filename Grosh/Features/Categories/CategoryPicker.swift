import SwiftData
import SwiftUI

/// Picks a category. A transaction's category is picked from the categories of its type the user may pick by hand
/// (``CategoryCatalog/pickerCategories(of:)``): hidden ones and those the app files itself are left out, and Debt/Loan
/// offers only Loan and Debt; the current selection still shows when it isn't offered any more. A filter picks from
/// every category of every type, hidden and locked ones included, or none.
struct CategoryPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: Category?
    private let offered: CategoryChoiceList.Offered
    /// The first choice, which picks no category, such as "Any". `nil` offers categories only.
    private let noneTitle: LocalizedStringKey?

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
            CategoryChoiceList(title: title, offered: offered, noneTitle: noneTitle, selection: $selection)
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

/// The list ``CategoryPicker`` pushes: the offered categories in tree order, subcategories indented.
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
    @Binding var selection: Category?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Keeps the list current when categories change.
    @Query private var categories: [Category]

    var body: some View {
        List {
            if noneTitle != nil {
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
        .navigationTitle(title)
    }

    /// One section of choices: under its type's name when every category is offered.
    private struct ChoiceSection: Identifiable {
        let title: String?
        let categories: [Category]
        var id: String { title ?? "" }
    }

    private var sections: [ChoiceSection] {
        switch offered {
        case .pickable(let type):
            [ChoiceSection(title: nil, categories: (try? CategoryCatalog(context: context).pickerCategories(of: type)) ?? [])]
        case .every:
            CategoryType.allCases
                .map { ChoiceSection(title: $0.title, categories: CategoryCatalog.tree(of: $0, from: categories)) }
                .filter { !$0.categories.isEmpty }
        }
    }

    private func row(_ category: Category?) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack {
                if let category {
                    CategoryLabel(category: category)
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
