import Foundation
import SwiftData

/// A notification on a reminder day: what the Loan and Debt reminders, the Estimated-amount reminders and the Owes me
/// reminders have in common.
nonisolated protocol PendingReminder: Hashable, Sendable {
    /// Marks the pending notifications of this sort, so replacing them leaves any other alone.
    static var identifierPrefix: String { get }
    /// The category the notification is posted in, which is what a notification action hangs off, or `nil` for none.
    static var categoryIdentifier: String? { get }
    /// The record it reminds of: a transaction, or an Expected reimbursement.
    var original: PersistentIdentifier { get }
    var day: CalendarDay { get }
    /// When the notification arrives.
    var arrival: ReminderArrival { get set }
    var title: String { get }
    var body: String { get }
    /// What the "Text them" action on the notification needs, kept in the notification itself, or `nil` for a
    /// reminder that names no Person.
    var textThem: TextThemPayload? { get }
}

extension PendingReminder {
    /// Whether `other` reminds of the same record on the same day, whatever it says by now.
    func isSameReminder(as other: Self) -> Bool {
        original == other.original && day == other.day
    }

    nonisolated static var categoryIdentifier: String? { nil }

    nonisolated var textThem: TextThemPayload? { nil }
}

/// When a reminder's notification arrives.
nonisolated enum ReminderArrival: Hashable, Sendable {
    /// At ``hour`` on the reminder day.
    case onItsDay
    /// As soon as it is scheduled: it was set for today once that hour had passed.
    case rightAway

    /// The hour of its day a reminder arrives at: 09:00.
    static let hour = 9
}

/// Where reminders go: the system's local notifications in the app, a stand-in in tests.
protocol ReminderScheduler {
    /// Asks the user to allow notifications, unless they already answered. Returns whether they are allowed.
    func requestPermission() async -> Bool
    /// Makes `reminders` the pending reminders of their sort, whether Loan and Debt or Estimated-amount ones, replacing
    /// every one of that sort scheduled before. Schedules nothing while notifications aren't allowed.
    func replacePending<Reminder: PendingReminder>(_ reminders: [Reminder]) async
}
