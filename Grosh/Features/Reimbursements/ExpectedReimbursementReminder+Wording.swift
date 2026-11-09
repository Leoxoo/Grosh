import Foundation

extension ExpectedReimbursementReminder {
    /// "Owes you", the notification's title.
    var title: String {
        String(localized: Strings.OwesMe.reminderTitle)
    }

    /// Who owes what for which Expense: "Alex owes you $30 for Dinner.", or "Alex owes you for Dinner." while the
    /// amount isn't known.
    var body: String {
        guard let outstanding else {
            return String(localized: Strings.OwesMe.reminderBody(personName, expense))
        }
        return String(localized: Strings.OwesMe.reminderBody(personName, outstanding.formatted(), expense))
    }
}
