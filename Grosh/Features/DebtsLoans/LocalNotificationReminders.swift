import SwiftData
import SwiftUI
import UserNotifications

/// Schedules Loan, Debt and Estimated-amount reminders as local notifications, at 09:00 on each reminder day or right
/// away.
struct LocalNotificationReminders: ReminderScheduler {
    func requestPermission() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    func replacePending<Reminder: PendingReminder>(_ reminders: [Reminder]) async {
        let prefix = Reminder.identifierPrefix
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(index)",
                content: content,
                trigger: reminder.trigger
            )
            try? await center.add(request)
        }
    }
}

private extension PendingReminder {
    /// At 09:00 on the reminder day, or a moment from now.
    var trigger: UNNotificationTrigger {
        switch arrival {
        case .onItsDay:
            let when = DateComponents(year: day.year, month: day.month, day: day.day, hour: ReminderArrival.hour)
            return UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        case .rightAway:
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
    }
}

/// Keeps the pending notifications of one sort of reminder in step with the store: whenever a reminder day, a payment, a
/// settlement or a confirmed amount changes what should be pending, they are replaced. The first reminder asks to send
/// notifications.
private struct ReminderSync<Source: ReminderSource>: ViewModifier {
    @Query private var transactions: [Transaction]
    @Environment(\.today) private var today
    /// What the last sync handed over, so a reminder set for today after 09:00 arrives once.
    @State private var earlier: [Source.Reminder]?

    init(_ source: Source.Type) {
        _transactions = Query(Source.transactions)
    }

    func body(content: Content) -> some View {
        let source = Source(transactions)
        let reminders = source.reminders(from: today)
        content
            .task(id: reminders) {
                // The moment, not just the day: once 09:00 has passed, a reminder for today arrives right away.
                await source.reschedule(at: .now, after: earlier, using: LocalNotificationReminders())
                earlier = reminders
            }
    }
}

extension View {
    /// Keeps the Loan and Debt reminders scheduled as local notifications in step with the store. Use once, at the
    /// app's top level.
    func syncsDebtReminders() -> some View {
        modifier(ReminderSync(DebtsAndLoans.self))
    }

    /// Keeps the Estimated-amount reminders scheduled as local notifications in step with the store. Use once, at the
    /// app's top level.
    func syncsEstimateReminders() -> some View {
        modifier(ReminderSync(EstimatedAmounts.self))
    }
}
