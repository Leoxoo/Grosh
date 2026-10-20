import Foundation
import SwiftData

/// A notification on a reminder day: what the Loan and Debt reminders, the Estimated-amount reminders and the Owes me
/// reminders have in common.
nonisolated protocol PendingReminder: Hashable, Sendable {
    /// Marks the pending notifications of this sort, so replacing them leaves any other alone.
    static var identifierPrefix: String { get }
    /// The category the notification is posted in, which is what a notification action hangs off, or `nil` for none.
    static var categoryIdentifier: String? { get }
    /// The record it reminds of: a transaction, or an Expected reimbursement.
    var original: PersistentIdentifier { get }
    var day: CalendarDay { get }
    /// When the notification arrives.
    var arrival: ReminderArrival { get set }
    var title: String { get }
    var body: String { get }
    /// What an action on the notification needs to know, kept in the notification itself.
    var userInfo: [String: String] { get }
}

extension PendingReminder {
    /// Whether `other` reminds of the same transaction on the same day, whatever it says by now.
    func isSameReminder(as other: Self) -> Bool {
        original == other.original && day == other.day
    }

    nonisolated static var categoryIdentifier: String? { nil }

    nonisolated var userInfo: [String: String] { [:] }
}

/// A notification on the reminder day of an open Loan or Debt, saying who it is with and what is outstanding.
///
/// Like the Owes me reminder it is posted in a ``categoryIdentifier`` and carries a ``userInfo``, which is what its
/// "Text them" action needs (``TextReminder``).
nonisolated struct DebtReminder: PendingReminder {
    static let identifierPrefix = "grosh.debt-reminder."
    /// What a notification action registers against.
    static let categoryIdentifier: String? = "grosh.debt"

    /// The Loan or Debt it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    /// The name of the Person the Loan or Debt is with.
    let withName: String
    let outstanding: Money
    /// A Loan (they owe the user) or a Debt (the user owes them).
    let kind: LoanOrDebtKind
    /// The phone number of the Person it is with, when they have one.
    var phone: String?
    var arrival = ReminderArrival.onItsDay

    var userInfo: [String: String] {
        typealias Key = ExpectedReimbursementReminder.InfoKey
        var info = [
            Key.person: withName, Key.amountCents: String(outstanding.cents),
            Key.currencyCode: outstanding.currencyCode,
        ]
        if let phone { info[Key.phone] = phone }
        if kind == .debt { info[Key.youOwe] = "true" }
        return info
    }
}

/// When a reminder's notification arrives.
nonisolated enum ReminderArrival: Hashable, Sendable {
    /// At ``hour`` on the reminder day.
    case onItsDay
    /// As soon as it is scheduled: it was set for today once that hour had passed.
    case rightAway

    /// The hour of its day a reminder arrives at: 09:00.
    static let hour = 9
}

/// Where reminders go: the system's local notifications in the app, a stand-in in tests.
protocol ReminderScheduler {
    /// Asks the user to allow notifications, unless they already answered. Returns whether they are allowed.
    func requestPermission() async -> Bool
    /// Makes `reminders` the pending reminders of their sort, whether Loan and Debt or Estimated-amount ones, replacing
    /// every one of that sort scheduled before. Schedules nothing while notifications aren't allowed.
    func replacePending<Reminder: PendingReminder>(_ reminders: [Reminder]) async
}

/// What the Home bell and the notifications remind of.
protocol ReminderSource {
    associatedtype Reminder: PendingReminder

    /// The notifications that should be pending: one for each reminder day `today` or later, the soonest first.
    func reminders(from today: CalendarDay) -> [Reminder]
}

/// A ``ReminderSource`` made from the transactions it is fetched from.
protocol TransactionReminderSource: ReminderSource {
    /// Every transaction it is made from. A source made from them stays current, since a change to one changes what
    /// this fetches.
    static var transactions: FetchDescriptor<Transaction> { get }

    init(_ transactions: [Transaction])
}

extension ReminderSource {
    /// The notifications to keep pending at `now`: the ``reminders(from:)`` of that day, each arriving at 09:00 on its
    /// day. Once 09:00 has passed, one for today arrives right away when it is new since `earlier` (what the previous
    /// sync handed over), and is left out otherwise, since it has arrived already. Before the first sync of a run
    /// (`earlier` is `nil`), every one for today counts as arrived.
    func reminders(at now: Date, calendar: Calendar = .current, after earlier: [Reminder]?) -> [Reminder] {
        let today = CalendarDay(now, in: calendar)
        let hasPassedTheHour = calendar.component(.hour, from: now) >= ReminderArrival.hour
        return reminders(from: today).compactMap { reminder in
            guard reminder.day == today, hasPassedTheHour else { return reminder }
            guard let earlier, !earlier.contains(where: reminder.isSameReminder) else { return nil }
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

extension DebtsAndLoans: TransactionReminderSource {
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
            let person = loanOrDebt.original.orderedPeople.first
            return DebtReminder(
                original: loanOrDebt.original.persistentModelID, day: day, withName: person?.name ?? "",
                outstanding: loanOrDebt.outstanding, kind: loanOrDebt.kind, phone: person?.phone
            )
        }
        .sorted { $0.day < $1.day }
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
