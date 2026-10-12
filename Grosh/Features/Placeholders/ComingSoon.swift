import Foundation

/// The parts of the app that are intentionally empty in v1, and what each one says while it waits.
enum ComingSoon: CaseIterable {
    case budgets
    case topSpending

    /// The coming-soon cards on Home, in the order they appear.
    static let homeCards: [ComingSoon] = [.topSpending]

    var title: String {
        switch self {
        case .budgets: String(localized: "Budgets")
        case .topSpending: String(localized: "Top spending")
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
            String(localized: "Set a spending limit for a category and see how much is left each month.")
        case .topSpending:
            String(localized: "Your biggest spending categories this month will appear here.")
        }
    }
}
