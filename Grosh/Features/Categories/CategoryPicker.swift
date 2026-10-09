import SwiftData
import SwiftUI

/// Picks the category a transaction is filed under, from the categories of `type` the user may pick by hand
/// (``CategoryCatalog/pickerCategories(of:)``): hidden ones and those the app files itself are left out, and
/// Debt/Loan offers only Loan and Debt. The current selection still shows when it isn't offered any more.
struct CategoryPicker: View {
    let title: LocalizedStringKey
    let type: CategoryType
    @Binding var selection: Category?

    var body: some View {
        NavigationLink {
            CategoryChoiceList(title: title, type: type, selection: $selection)
        } label: {
            LabeledContent(title) {
                if let selection {
                    CategoryLabel(category: selection, indentsSubcategories: false)
                        .foregroundStyle(.primary)
                } else {
                    Text("Choose")
                }
            }
        }
    }
}

/// The list ``CategoryPicker`` pushes: the offered categories in tree order, subcategories indented.
private struct CategoryChoiceList: View {
    let title: LocalizedStringKey
    let type: CategoryType
    @Binding var selection: Category?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    /// Keeps the list current when categories change.
    @Query private var categories: [Category]

    private var choices: [Category] {
        (try? CategoryCatalog(context: context).pickerCategories(of: type)) ?? []
    }

    var body: some View {
        List(choices) { category in
            Button {
                selection = category
                dismiss()
            } label: {
                HStack {
                    CategoryLabel(category: category)
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
        .navigationTitle(title)
    }
}
