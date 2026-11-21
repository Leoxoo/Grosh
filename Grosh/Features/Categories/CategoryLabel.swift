import SwiftUI

extension CategoryType {
    var title: String {
        switch self {
        case .expense: String(localized: Strings.Common.expense)
        case .income: String(localized: Strings.Common.income)
        case .debtLoan: String(localized: Strings.Categories.debtLoan)
        case .system: String(localized: Strings.Categories.system)
        }
    }
}

/// A category's icon on its colored circle; a question mark on gray for a transaction filed under none. A Subscription
/// shows its own cropped icon in place of the symbol, when it has one.
struct CategoryIcon: View {
    let category: Category?
    var subscriptionIcon: Data?
    var size: CGFloat = 32

    var body: some View {
        if let subscriptionIcon, let image = CroppedPhoto.image(from: subscriptionIcon) {
            CroppedPhotoImage(image: image, height: size)
        } else {
            SymbolCircle(
                symbolName: category?.symbolName ?? Category.placeholderSymbolName, color: category?.color ?? .gray,
                size: size
            )
        }
    }
}

/// A category's icon and name, as rows and pickers show it. Subcategories are indented under their parent, with a dot
/// in the indent.
struct CategoryLabel: View {
    let category: Category
    var indentsSubcategories = true

    var body: some View {
        HStack(spacing: 12) {
            if indentsSubcategories && category.parent != nil {
                // A dot in the indent marks a subcategory, so it reads as one of its parent's at a glance.
                Circle()
                    .fill(.tertiary)
                    .frame(width: 6, height: 6)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }
            CategoryIcon(category: category)
            Text(category.name)
        }
    }
}
