import Foundation

/// The parts of the app that are intentionally empty in v1, and what each one says while it waits.
enum ComingSoon: CaseIterable {
    case budgets
    case reportThisMonth
    case topSpending

    /// The coming-soon cards on Home, in the order they appear.
    static let homeCards: [ComingSoon] = [.reportThisMonth, .topSpending]

    var title: String {
        switch self {
        case .budgets: String(localized: "Budgets")
        case .reportThisMonth: String(localized: "Report this month")
        case .topSpending: String(localized: "Top spending")
        }
    }

    /// An SF Symbol name.
    var systemImage: String {
        switch self {
        case .budgets: "chart.pie"
        case .reportThisMonth: "chart.bar.xaxis"
        case .topSpending: "list.number"
        }
    }

    /// One or two sentences on what the feature will do.
    var message: String {
        switch self {
        case .budgets:
            String(localized: "Set a spending limit for a category and see how much is left each month.")
        case .reportThisMonth:
            String(localized: "A chart of this month's income and spending will appear here.")
        case .topSpending:
            String(localized: "Your biggest spending categories this month will appear here.")
        }
    }
}
