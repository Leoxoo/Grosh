import SwiftData
import SwiftUI
import UserNotifications

/// Schedules Loan, Debt, Estimated-amount and Owes me reminders as local notifications, at 09:00 on each reminder day
/// or right away.
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
            if let category = Reminder.categoryIdentifier {
                content.categoryIdentifier = category
            }
            content.userInfo = reminder.userInfo
            let request = UNNotificationRequest(
                identifier: "\(prefix)\(index)",
                content: content,
                trigger: reminder.trigger
            )
            try? await center.add(request)
        }
    }
}

extension LocalNotificationReminders {
    /// The identifier of the "Text them" notification action.
    nonisolated static let textThemAction = "grosh.text-them"

    /// Gives the reminders that name a Person (Owes me, Loan and Debt) a "Text them" action, which opens the Messages
    /// compose sheet for that Person (``ReminderActionHandler``). The action only opens the app; the user taps Send, and
    /// nothing is sent without it. Done once at launch, before any notification can arrive.
    static func registerActions(on center: UNUserNotificationCenter = .current()) {
        let textThem = UNNotificationAction(
            identifier: textThemAction, title: String(localized: "Text them"), options: [.foreground]
        )
        let categories = [ExpectedReimbursementReminder.categoryIdentifier, DebtReminder.categoryIdentifier]
            .compactMap { $0 }
            .map { UNNotificationCategory(identifier: $0, actions: [textThem], intentIdentifiers: [], options: []) }
        center.setNotificationCategories(Set(categories))
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
    @Query private var records: [Source.Record]
    /// What the last sync handed over, so a reminder set for today after 09:00 arrives once.
    @State private var earlier: [Source.Reminder]?

    init(_ source: Source.Type) {
        _records = Query(Source.records)
    }

    func body(content: Content) -> some View {
        let source = Source(records)
        let reminders = source.reminders(from: .today)
        content
            .task(id: reminders) {
                await source.reschedule(at: .now, after: earlier, using: LocalNotificationReminders())
                earlier = reminders
            }
    }
}

extension View {
    /// Keeps the Owes me reminders scheduled as local notifications in step with the store: whenever an expectation is
    /// made, paid, closed, forgiven, removed or has its reminder changed, or its Expense goes to Recently Deleted or
    /// comes back. Use once, at the app's top level.
    func syncsExpectedReimbursementReminders() -> some View {
        modifier(ReminderSync(ExpectedReimbursements.self))
    }

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
