import Foundation
import SwiftData

/// A notification on the reminder day of an open Expected reimbursement, saying who owes what for which Expense: "Alex
/// owes you $30 for Dinner." (ADR-0010). It arrives at 09:00 like the other reminders and the Home bell lists the
/// expectation from that day until it is settled.
///
/// The notification is posted in ``categoryIdentifier`` and carries ``textThem``, which is everything an action on it
/// (such as Text them) needs: the Person, their phone, the Expense and the amount.
nonisolated struct ExpectedReimbursementReminder: PendingReminder {
    static let identifierPrefix = "grosh.owes-me-reminder."
    /// What a notification action registers against.
    static let categoryIdentifier: String? = "grosh.owes-me"

    /// The Expected reimbursement it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    /// The Person who owes, or `nil` for none.
    let person: PersistentIdentifier?
    /// The name of the Person who owes.
    let personName: String
    /// The Person's phone number, when they have one.
    let phone: String?
    /// What the Expense was: its note, else its category's name.
    let expense: String
    /// What is outstanding, or `nil` for an open amount.
    let outstanding: Money?
    var arrival = ReminderArrival.onItsDay

    var textThem: TextThemPayload? {
        TextThemPayload(
            person: person, personName: personName, phone: phone, expense: expense, outstanding: outstanding
        )
    }
}

extension ExpectedReimbursements: ReminderSource {
    static var records: FetchDescriptor<ExpectedReimbursement> { all }

    static func reminderDay(of expectation: ExpectedReimbursement) -> CalendarDay? { expectation.openReminderDay }

    static func reminder(for expectation: ExpectedReimbursement, on day: CalendarDay) -> ExpectedReimbursementReminder {
        ExpectedReimbursementReminder(
            original: expectation.persistentModelID, day: day, person: expectation.person?.persistentModelID,
            personName: expectation.personName, phone: expectation.person?.phone, expense: expectation.expenseTitle,
            outstanding: expectation.outstanding
        )
    }
}
