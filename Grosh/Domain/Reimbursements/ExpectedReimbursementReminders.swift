import Foundation
import SwiftData

/// A notification on the reminder day of an open Expected reimbursement, saying who owes what for which Expense: "Alex
/// owes you $30 for Dinner." (ADR-0010). It arrives at 09:00 like the other reminders and the Home bell lists the
/// expectation from that day until it is settled.
///
/// The notification is posted in ``categoryIdentifier`` and carries ``userInfo``, which is everything an action on it
/// (such as Text them) needs: the Person, their phone, the Expense and the amount.
nonisolated struct ExpectedReimbursementReminder: PendingReminder {
    static let identifierPrefix = "grosh.owes-me-reminder."
    /// What a notification action registers against.
    static let categoryIdentifier: String? = "grosh.owes-me"

    /// The keys of ``userInfo``.
    enum InfoKey {
        static let person = "person"
        static let phone = "phone"
        static let expense = "expense"
        /// What is outstanding in cents; missing for an open amount.
        static let amountCents = "amountCents"
        static let currencyCode = "currencyCode"
    }

    /// The Expected reimbursement it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    /// The name of the Person who owes.
    let personName: String
    /// The Person's phone number, when they have one.
    let phone: String?
    /// What the Expense was: its note, else its category's name.
    let expense: String
    /// What is outstanding, or `nil` for an open amount.
    let outstanding: Money?
    var arrival = ReminderArrival.onItsDay

    var userInfo: [String: String] {
        var info = [InfoKey.person: personName, InfoKey.expense: expense]
        if let phone { info[InfoKey.phone] = phone }
        if let outstanding {
            info[InfoKey.amountCents] = String(outstanding.cents)
            info[InfoKey.currencyCode] = outstanding.currencyCode
        }
        return info
    }
}

extension ExpectedReimbursements: ReminderSource {
    /// The notifications that should be pending: one for each open expectation whose reminder day is `today` or later,
    /// the soonest first. A settled one (paid back, closed or forgiven) has none, and neither has one whose Expense is in
    /// Recently Deleted; one whose day has passed is listed by the bell instead.
    func reminders(from today: CalendarDay) -> [ExpectedReimbursementReminder] {
        open.compactMap { expectation in
            guard let day = expectation.reminderDay, day >= today else { return nil }
            return ExpectedReimbursementReminder(
                original: expectation.persistentModelID, day: day, personName: expectation.personName,
                phone: expectation.person?.phone, expense: expectation.expenseTitle,
                outstanding: expectation.outstanding
            )
        }
        .sorted { $0.day < $1.day }
    }
}
