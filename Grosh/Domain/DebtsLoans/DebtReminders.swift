import Foundation
import SwiftData

/// A notification on the reminder day of an open Loan or Debt, saying who it is with and what is outstanding.
nonisolated struct DebtReminder: Hashable, Sendable {
    /// The Loan or Debt it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    let withName: String
    let outstanding: Money
    /// A Loan (they owe the user) or a Debt (the user owes them).
    let kind: LoanOrDebtKind
    /// When the notification arrives.
    var arrival = ReminderArrival.onItsDay

    /// The hour of its day a reminder arrives at: 09:00.
    static let hour = 9

    /// Whether `other` reminds of the same Loan or Debt on the same day, whatever is outstanding by now.
    func isSameReminder(as other: DebtReminder) -> Bool {
        original == other.original && day == other.day
    }
}

/// When a reminder's notification arrives.
nonisolated enum ReminderArrival: Hashable, Sendable {
    /// At ``DebtReminder/hour`` on the reminder day.
    case onItsDay
    /// As soon as it is scheduled: it was set for today once that hour had passed.
    case rightAway
}

/// Where Loan and Debt reminders go: the system's local notifications in the app, a stand-in in tests.
protocol ReminderScheduler {
    /// Asks the user to allow notifications, unless they already answered. Returns whether they are allowed.
    func requestPermission() async -> Bool
    /// Makes `reminders` the pending Loan and Debt reminders, replacing every one scheduled before. Schedules
    /// nothing while notifications aren't allowed.
    func replacePendingReminders(with reminders: [DebtReminder]) async
}

extension DebtsAndLoans {
    /// The open Loans and Debts whose reminder day is `today` or earlier, the earliest first: what the Home bell
    /// lists. A settled one is never due.
    func due(on today: CalendarDay) -> [LoanOrDebt] {
        open.filter { $0.original.reminderDay.map { $0 <= today } ?? false }
            .sorted { $0.original.reminderDay ?? today < $1.original.reminderDay ?? today }
    }

    /// The notifications that should be pending: one for each open Loan or Debt whose reminder day is `today` or
    /// later, the soonest first. A settled one has none, and one whose day has passed is listed by the bell instead.
    func reminders(from today: CalendarDay) -> [DebtReminder] {
        open.compactMap { loanOrDebt in
            guard let day = loanOrDebt.original.reminderDay, day >= today else { return nil }
            return DebtReminder(
                original: loanOrDebt.original.persistentModelID, day: day, withName: loanOrDebt.original.withName,
                outstanding: loanOrDebt.outstanding, kind: loanOrDebt.kind
            )
        }
        .sorted { $0.day < $1.day }
    }

    /// The notifications to keep pending at `now`: the ``reminders(from:)`` of that day, each arriving at 09:00 on
    /// its day. Once 09:00 has passed, one for today arrives right away when it is new since `earlier` (what the
    /// previous sync handed over), and is left out otherwise, since it has arrived already. Before the first sync of
    /// a run (`earlier` is `nil`), every one for today counts as arrived.
    func reminders(at now: Date, calendar: Calendar = .current, after earlier: [DebtReminder]?) -> [DebtReminder] {
        let today = CalendarDay(now, in: calendar)
        let hasPassedTheHour = calendar.component(.hour, from: now) >= DebtReminder.hour
        return reminders(from: today).compactMap { reminder in
            guard reminder.day == today, hasPassedTheHour else { return reminder }
            guard let earlier, !earlier.contains(where: reminder.isSameReminder) else { return nil }
            var rightAway = reminder
            rightAway.arrival = .rightAway
            return rightAway
        }
    }

    /// Hands `scheduler` the ``reminders(at:calendar:after:)`` to keep pending, replacing those scheduled before.
    /// When there is any, it first asks the user to allow notifications (the system asks only once), so the first
    /// reminder is scheduled as soon as they allow it.
    func reschedule(
        at now: Date, calendar: Calendar = .current, after earlier: [DebtReminder]?,
        using scheduler: some ReminderScheduler
    ) async {
        let reminders = reminders(at: now, calendar: calendar, after: earlier)
        if !reminders.isEmpty {
            _ = await scheduler.requestPermission()
        }
        await scheduler.replacePendingReminders(with: reminders)
    }
}

extension TransactionDefaults {
    /// The day a Loan's or Debt's reminder starts at when the user turns it on: a week from `today`.
    static func reminderDay(from today: CalendarDay) -> CalendarDay {
        today.adding(days: 7)
    }
}

extension Transaction {
    /// Moves or clears this Loan's or Debt's reminder day, whatever has been paid on it. Nothing else about it
    /// changes. Saves.
    func setReminder(_ day: CalendarDay?) throws {
        guard isLoanOrDebt else { throw DebtLoanRuleError.notALoanOrDebt }
        reminderDay = day
        try modelContext?.save()
    }
}
