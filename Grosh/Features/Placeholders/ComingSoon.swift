import Foundation

/// The parts of the app that are intentionally empty in v1, and what each one says while it waits.
enum ComingSoon: CaseIterable {
    case budgets
    case topSpending

    /// The coming-soon cards on Home, in the order they appear.
    static let homeCards: [ComingSoon] = [.topSpending]

    var title: String {
        switch self {
        case .budgets: String(localized: Strings.Screens.budgets)
        case .topSpending: String(localized: Strings.Settings.topSpending)
        }
    }

    /// An SF Symbol name.
    var systemImage: String {
        switch self {
        case .budgets: "chart.pie"
        case .topSpending: "list.number"
        }
    }

    /// One or two sentences on what the feature will do.
    var message: String {
        switch self {
        case .budgets:
            String(localized: Strings.Settings.budgetsMessage)
        case .topSpending:
            String(localized: Strings.Settings.topSpendingMessage)
        }
    }
}
