import SwiftData
import SwiftUI
import UserNotifications

/// Schedules Loan and Debt reminders as local notifications, at 9:00 on each reminder day.
struct LocalNotificationReminders: ReminderScheduler {
    /// Marks the pending notifications that are Loan and Debt reminders, so replacing them leaves any other alone.
    private static let identifierPrefix = "grosh.debt-reminder."
    /// The hour of the reminder day a notification arrives at.
    private static let hour = 9

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
            let when = DateComponents(
                year: reminder.day.year, month: reminder.day.month, day: reminder.day.day, hour: Self.hour
            )
            let request = UNNotificationRequest(
                identifier: "\(Self.identifierPrefix)\(index)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            )
            try? await center.add(request)
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
/// settlement changes what should be pending, they are replaced.
private struct DebtReminderSync: ViewModifier {
    @Query(DebtsAndLoans.transactions) private var transactions: [Transaction]

    func body(content: Content) -> some View {
        let today = CalendarDay.today
        let list = DebtsAndLoans(transactions)
        content
            .task(id: list.reminders(from: today)) {
                await list.reschedule(from: today, using: LocalNotificationReminders())
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
