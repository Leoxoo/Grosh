import Foundation

extension RecurringKind {
    /// The kind's name in the Kind picker, such as "Bill".
    var title: String {
        switch self {
        case .bill: String(localized: "Bill")
        case .subscription: String(localized: "Subscription")
        case .purchase: String(localized: "Purchase")
        case .regular: String(localized: "Regular")
        }
    }

    /// The kind's heading on the Recurring tab, such as "Bills".
    var sectionTitle: String {
        switch self {
        case .bill: String(localized: "Bills")
        case .subscription: String(localized: "Subscriptions")
        case .purchase: String(localized: "Purchases")
        case .regular: String(localized: "Regular")
        }
    }
}
