import Foundation

extension RecurringKind {
    /// The kind's name in the Kind picker, such as "Bill".
    var title: String {
        switch self {
        case .bill: String(localized: Strings.Recurring.bill)
        case .subscription: String(localized: Strings.Recurring.subscription)
        case .purchase: String(localized: Strings.Recurring.purchase)
        case .regular: String(localized: Strings.Recurring.regular)
        }
    }

    /// The kind's heading on the Recurring tab, such as "Bills".
    var sectionTitle: String {
        switch self {
        case .bill: String(localized: Strings.Recurring.bills)
        case .subscription: String(localized: Strings.Recurring.subscriptions)
        case .purchase: String(localized: Strings.Recurring.purchases)
        case .regular: String(localized: Strings.Recurring.regular)
        }
    }
}
