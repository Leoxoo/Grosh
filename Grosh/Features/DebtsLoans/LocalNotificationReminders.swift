import SwiftData
import SwiftUI
import UserNotifications

/// Schedules Loan, Debt and Estimated-amount reminders as local notifications, at 09:00 on each reminder day or right
/// away.
struct LocalNotificationReminders: ReminderScheduler {
    /// Marks the pending notifications that are Loan and Debt reminders, so replacing them leaves any other alone.
    private static let identifierPrefix = "grosh.debt-reminder."
    /// Marks the pending notifications that are Estimated-amount reminders, so replacing them leaves any other alone.
    private static let estimatePrefix = "grosh.estimate-reminder."

    func requestPermission() async -> Bool {
        let options: UNAuthorizationOptions = [.alert, .sound]
        return (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
    }

    func replacePendingReminders(with reminders: [DebtReminder]) async {
        await replacePending(prefix: Self.identifierPrefix, reminders.map { Notice($0) })
    }

    func replacePendingEstimateReminders(with reminders: [EstimateReminder]) async {
        await replacePending(prefix: Self.estimatePrefix, reminders.map { Notice($0) })
    }

    /// Replaces the pending notifications under `prefix` with one for each of `notices`. Schedules none while
    /// notifications aren't allowed.
    private func replacePending(prefix: String, _ notices: [Notice]) async {
        let center = UNUserNotificationCenter.current()
        let scheduled = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: scheduled)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        for (index, notice) in notices.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(index)",
                content: content,
                trigger: notice.trigger
            )
            try? await center.add(request)
        }
    }
}

/// What one pending notification says, and when it arrives.
private struct Notice {
    let title: String
    let body: String
    let day: CalendarDay
    let arrival: ReminderArrival

    init(_ reminder: DebtReminder) {
        title = reminder.title
        body = reminder.body
        day = reminder.day
        arrival = reminder.arrival
    }

    init(_ reminder: EstimateReminder) {
        title = reminder.title
        body = reminder.body
        day = reminder.day
        arrival = reminder.arrival
    }

    /// At 09:00 on the reminder day, or a moment from now.
    var trigger: UNNotificationTrigger {
        switch arrival {
        case .onItsDay:
            let when = DateComponents(year: day.year, month: day.month, day: day.day, hour: DebtReminder.hour)
            return UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        case .rightAway:
            return UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        }
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

/// Keeps the pending Estimated-amount notifications in step with the store, as ``DebtReminderSync`` does for Loans and
/// Debts. Confirming an amount takes its notification away.
private struct EstimateReminderSync: ViewModifier {
    @Query(EstimatedAmounts.transactions) private var transactions: [Transaction]
    /// What the last sync handed over, so a reminder set for today after 09:00 arrives once.
    @State private var earlier: [EstimateReminder]?

    func body(content: Content) -> some View {
        let estimates = EstimatedAmounts(transactions)
        let reminders = estimates.reminders(from: .today)
        content
            .task(id: reminders) {
                await estimates.reschedule(at: .now, after: earlier, using: LocalNotificationReminders())
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

    /// Keeps the Estimated-amount reminders scheduled as local notifications in step with the store. Use once, at the
    /// app's top level.
    func syncsEstimateReminders() -> some View {
        modifier(EstimateReminderSync())
    }
}
