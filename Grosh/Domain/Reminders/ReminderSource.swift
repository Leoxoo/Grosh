import Foundation
import SwiftData

/// What the Home bell and the notifications remind of, made from the records it is fetched from: the open Loans and
/// Debts, the Estimated transactions, the open Expected reimbursements.
protocol ReminderSource {
    associatedtype Reminder: PendingReminder
    /// What it is made from: transactions, or Expected reimbursements.
    associatedtype Record: PersistentModel
    /// What the Home bell lists: a Loan or Debt, an Estimated transaction, an Expected reimbursement.
    associatedtype Item

    /// Every record it is made from. A source made from them stays current, since a change to one changes what this
    /// fetches.
    static var records: FetchDescriptor<Record> { get }

    init(_ records: [Record])

    /// What still waits on the user, the only ones that remind: a settled one never does.
    var open: [Item] { get }

    /// The day `item` reminds the user on, or `nil` for none.
    static func reminderDay(of item: Item) -> CalendarDay?

    /// The notification for `item` on its reminder day, `day`.
    static func reminder(for item: Item, on day: CalendarDay) -> Reminder
}

extension ReminderSource {
    /// What is open and reminds on `today` or earlier, the earliest first: what the Home bell lists.
    func due(on today: CalendarDay) -> [Item] {
        withReminderDays.filter { ReminderDay.isDue($0.day, on: today) }.map(\.item)
    }

    /// The notifications that should be pending: one for each open item reminding on `today` or later, the soonest
    /// first. One whose day has passed is listed by the bell instead.
    func reminders(from today: CalendarDay) -> [Reminder] {
        withReminderDays.filter { $0.day >= today }.map { Self.reminder(for: $0.item, on: $0.day) }
    }

    /// The open items that have a reminder day, with it, the soonest first.
    private var withReminderDays: [(item: Item, day: CalendarDay)] {
        open.compactMap { item in Self.reminderDay(of: item).map { (item, $0) } }
            .sorted { $0.day < $1.day }
    }

    /// The notifications to keep pending at `now`: the ``reminders(from:)`` of that day, each arriving at 09:00 on its
    /// day. Once 09:00 has passed, one for today arrives right away when it is new since `earlier` (what the previous
    /// sync handed over), and is left out otherwise, since it has arrived already. Before the first sync of a run
    /// (`earlier` is `nil`), every one for today counts as arrived.
    func reminders(at now: Date, calendar: Calendar = .current, after earlier: [Reminder]?) -> [Reminder] {
        let today = CalendarDay(now, in: calendar)
        let hasPassedTheHour = calendar.component(.hour, from: now) >= ReminderArrival.hour
        return reminders(from: today).compactMap { reminder in
            guard reminder.day == today, hasPassedTheHour else { return reminder }
            guard let earlier, !earlier.contains(where: { reminder.isSameReminder(as: $0) }) else { return nil }
            var rightAway = reminder
            rightAway.arrival = .rightAway
            return rightAway
        }
    }

    /// Hands `scheduler` the ``reminders(at:calendar:after:)`` to keep pending, replacing those scheduled before. When
    /// there is any, it first asks the user to allow notifications (the system asks only once), so the first reminder
    /// is scheduled as soon as they allow it.
    func reschedule(
        at now: Date, calendar: Calendar = .current, after earlier: [Reminder]?, using scheduler: some ReminderScheduler
    ) async {
        let reminders = reminders(at: now, calendar: calendar, after: earlier)
        if !reminders.isEmpty {
            _ = await scheduler.requestPermission()
        }
        await scheduler.replacePending(reminders)
    }
}
