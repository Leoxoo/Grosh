import Foundation

extension EstimateReminder {
    /// "Amount to confirm", the notification's title.
    var title: String {
        String(localized: Strings.Recurring.amountToConfirm)
    }

    /// What was estimated, and that the real amount is to be entered.
    var body: String {
        String(localized: Strings.Recurring.estimatedAt(name, estimate.formatted()))
    }
}
