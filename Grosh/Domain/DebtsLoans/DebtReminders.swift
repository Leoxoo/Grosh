import Foundation
import SwiftData

/// A notification on the reminder day of an open Loan or Debt, saying who it is with and what is outstanding.
nonisolated struct DebtReminder: Hashable, Sendable {
    let day: CalendarDay
    let withName: String
    let outstanding: Money
    /// A Loan (they owe the user) rather than a Debt (the user owes them).
    let isLoan: Bool
}

/// Where Loan and Debt reminders go: the system's local notifications in the app, a stand-in in tests.
protocol ReminderScheduler {
    /// Asks the user to allow notifications, unless they already answered. Returns whether they are allowed.
    func requestPermission() async -> Bool
    /// Makes `reminders` the pending Loan and Debt reminders, replacing every one scheduled before.
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
        open.compactMap { item in
            guard let day = item.original.reminderDay, day >= today else { return nil }
            return DebtReminder(
                day: day, withName: item.original.withName, outstanding: item.outstanding,
                isLoan: item.isLoan
            )
        }
        .sorted { $0.day < $1.day }
    }

    /// Hands `scheduler` the ``reminders(from:)`` to keep pending, replacing those scheduled before.
    func reschedule(from today: CalendarDay, using scheduler: some ReminderScheduler) async {
        await scheduler.replacePendingReminders(with: reminders(from: today))
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
