import Testing
@testable import Grosh

/// Records what it is asked, in order, instead of asking the user or scheduling notifications. Notifications are always
/// allowed. It takes the pending reminders of one sort, `Reminder`, and fails the test if it is handed another.
@MainActor
final class RecordingReminderScheduler<Reminder: PendingReminder>: ReminderScheduler {
    enum Call: Equatable {
        case requestPermission
        case replacePending([Reminder])
    }

    private(set) var calls: [Call] = []

    func requestPermission() async -> Bool {
        calls.append(.requestPermission)
        return true
    }

    func replacePending<Sent: PendingReminder>(_ reminders: [Sent]) async {
        guard let reminders = reminders as? [Reminder] else {
            Issue.record("Expected \(Reminder.self) reminders but got \(Sent.self) ones.")
            return
        }
        calls.append(.replacePending(reminders))
    }
}
