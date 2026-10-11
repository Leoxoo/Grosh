import Foundation

extension EstimateReminder {
    /// "Amount to confirm", the notification's title.
    var title: String {
        String(localized: "Amount to confirm")
    }

    /// What was estimated, and that the real amount is to be entered.
    var body: String {
        String(localized: "\(name) was estimated at \(estimate.formatted()). Enter the real amount.")
    }
}
