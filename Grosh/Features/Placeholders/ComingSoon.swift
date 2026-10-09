/// The parts of the app that are intentionally empty in v1, and what each one says while it waits.
enum ComingSoon: CaseIterable {
    case budgets
    case reportThisMonth
    case topSpending
    case recurringTransactions

    /// The coming-soon cards on Home, in the order they appear.
    static let homeCards: [ComingSoon] = [.reportThisMonth, .topSpending]

    var title: String {
        switch self {
        case .budgets: "Budgets"
        case .reportThisMonth: "Report this month"
        case .topSpending: "Top spending"
        case .recurringTransactions: "Recurring transactions"
        }
    }

    /// An SF Symbol name.
    var systemImage: String {
        switch self {
        case .budgets: "chart.pie"
        case .reportThisMonth: "chart.bar.xaxis"
        case .topSpending: "list.number"
        case .recurringTransactions: "repeat"
        }
    }

    /// One or two sentences on what the feature will do.
    var message: String {
        switch self {
        case .budgets:
            "Set a spending limit for a category and see how much is left each month."
        case .reportThisMonth:
            "A chart of this month's income and spending will appear here."
        case .topSpending:
            "Your biggest spending categories this month will appear here."
        case .recurringTransactions:
            "Bills and income that repeat will be added for you on their dates."
        }
    }
}
