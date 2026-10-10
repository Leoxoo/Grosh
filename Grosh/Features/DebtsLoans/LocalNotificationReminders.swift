import SwiftData
import SwiftUI
import UserNotifications

/// Schedules Loan and Debt reminders as local notifications, at 09:00 on each reminder day or right away.
struct LocalNotificationReminders: ReminderScheduler {
    /// Marks the pending notifications that are Loan and Debt reminders, so replacing them leaves any other alone.
    private static let identifierPrefix = "grosh.debt-reminder."

    func requestPermission() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    func replacePendingReminders(with reminders: [DebtReminder]) async {
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for (index, reminder) in reminders.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(index)",
                content: content,
                trigger: reminder.trigger
            )
            try? await center.add(request)
        }
    }
}

private extension DebtReminder {
    /// At 09:00 on the reminder day, or a moment from now.
    var trigger: UNNotificationTrigger {
        switch arrival {
        case .onItsDay:
            let when = DateComponents(year: day.year, month: day.month, day: day.day, hour: Self.hour)
            return UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        case .rightAway:
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
    }
}

extension DebtReminder {
    /// "Loan reminder" or "Debt reminder".
    var title: String {
        isLoan ? String(localized: "Loan reminder") : String(localized: "Debt reminder")
    }

    /// Who owes whom, and how much is outstanding.
    var body: String {
        let amount = outstanding.formatted()
        return isLoan
            ? String(localized: "\(withName) owes you \(amount).")
            : String(localized: "You owe \(withName) \(amount).")
    }
}

/// Keeps the pending Loan and Debt notifications in step with the store: whenever a reminder day, a payment or a
/// settlement changes what should be pending, they are replaced. The first reminder asks to send notifications.
private struct DebtReminderSync: ViewModifier {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]
    /// What the last sync handed over, so a reminder set for today after 09:00 arrives once.
    @State private var earlier: [DebtReminder]?

    func body(content: Content) -> some View {
        let list = DebtsAndLoans(transactions)
        let reminders = list.reminders(from: .today)
        content
            .task(id: reminders) {
                await list.reschedule(at: .now, after: earlier, using: LocalNotificationReminders())
                earlier = reminders
            }
    }
}

extension View {
    /// Keeps the Loan and Debt reminders scheduled as local notifications in step with the store. Use once, at the
    /// app's top level.
    func syncsDebtReminders() -> some View {
        modifier(DebtReminderSync())
    }
}
