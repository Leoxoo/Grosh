import Foundation

extension ExpectedReimbursementReminder {
    /// "Owes you", the notification's title.
    var title: String {
        String(localized: "Owes you")
    }

    /// Who owes what for which Expense: "Alex owes you $30 for Dinner.", or "Alex owes you for Dinner." while the
    /// amount isn't known.
    var body: String {
        guard let outstanding else {
            return String(localized: "\(personName) owes you for \(expense).")
        }
        return String(localized: "\(personName) owes you \(outstanding.formatted()) for \(expense).")
    }
}
