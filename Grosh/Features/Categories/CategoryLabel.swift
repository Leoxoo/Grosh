import SwiftUI

extension CategoryType {
    /// The types the user sees, in order: the segments of Account → Categories and of the Add sheet.
    static let segments: [CategoryType] = [.expense, .income, .debtLoan]

    var title: String {
        switch self {
        case .expense: String(localized: "Expense")
        case .income: String(localized: "Income")
        case .debtLoan: String(localized: "Debt/Loan")
        case .system: String(localized: "System")
        }
    }
}

/// A category's icon on its colored circle; a question mark on gray for a transaction filed under none.
struct CategoryIcon: View {
    let category: Category?
    var size: CGFloat = 32

    var body: some View {
        SymbolCircle(symbolName: category?.symbolName ?? "questionmark", color: category?.color ?? .gray, size: size)
    }
}

/// A category's icon and name, as rows and pickers show it. Subcategories are indented under their parent.
struct CategoryLabel: View {
    let category: Category
    var indentsSubcategories = true

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category)
            Text(category.name)
        }
        .padding(.leading, indentsSubcategories && category.parent != nil ? 28 : 0)
    }
}
