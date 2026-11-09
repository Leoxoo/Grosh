import Foundation
import SwiftData

/// The rules every reminder day follows, whether a Loan's or Debt's, an Owes me's or an Estimated transaction's.
nonisolated enum ReminderDay {
    /// How many days later a reminder starts at when the user turns it on.
    static let daysLater = 7

    /// The day a reminder starts at when it is turned on: a week after `day`. A Loan or Debt counts from today; an Owes
    /// me from its Expense's day, since the Expense may be old.
    static func `default`(after day: CalendarDay) -> CalendarDay {
        day.adding(days: daysLater)
    }

    /// Whether a reminder on `day` is due on `today`: its day has come. `nil` (no reminder) never is.
    static func isDue(_ day: CalendarDay?, on today: CalendarDay) -> Bool {
        day.map { $0 <= today } ?? false
    }

    /// Whether something reminding on `first` is listed before something reminding on `second` among the open ones: a
    /// reminder day before none, an earlier reminder day before a later one, and otherwise as `isOlder` says, the
    /// older first.
    static func isListed(_ first: CalendarDay?, before second: CalendarDay?, otherwise isOlder: () -> Bool) -> Bool {
        switch (first, second) {
        case let (first?, second?) where first != second: first < second
        case (.some, nil): true
        case (nil, .some): false
        default: isOlder()
        }
    }
}

/// Something the user sets a reminder day on: a Loan or Debt, an Expected reimbursement.
nonisolated protocol RemindedRecord: PersistentModel {
    var reminderDay: CalendarDay? { get set }
    /// Throws why this record takes no reminder; returns when it takes one.
    func checkTakesReminder() throws
}

nonisolated extension RemindedRecord {
    /// Moves or clears the reminder day, whatever has been paid. Nothing else changes. Saves.
    func setReminder(_ day: CalendarDay?) throws {
        try checkTakesReminder()
        reminderDay = day
        try modelContext?.save()
    }
}

/// Something listed with its reminder day while it is open: a Loan or Debt, an Expected reimbursement.
protocol ListedWithReminder {
    /// The reminder day while it is open, or `nil` when it has none or is settled.
    var openReminderDay: CalendarDay? { get }
}

extension ListedWithReminder {
    /// Whether its reminder is due on `today`, so its row shows the day as urgent.
    func isReminderDue(on today: CalendarDay) -> Bool {
        ReminderDay.isDue(openReminderDay, on: today)
    }
}
