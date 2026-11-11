import Foundation
import SwiftData

/// A notification on the reminder day of an open Loan or Debt, saying who it is with and what is outstanding.
///
/// Like the Owes me reminder it is posted in a ``categoryIdentifier`` and carries a ``textThem`` payload, which is
/// what its "Text them" action needs (``TextReminder``).
nonisolated struct DebtReminder: PendingReminder {
    static let identifierPrefix = "grosh.debt-reminder."
    /// What a notification action registers against.
    static let categoryIdentifier: String? = "grosh.debt"

    /// The Loan or Debt it reminds of.
    let original: PersistentIdentifier
    let day: CalendarDay
    /// The Person the Loan or Debt is with, or `nil` for none.
    var person: PersistentIdentifier?
    /// The name of the Person the Loan or Debt is with.
    let withName: String
    let outstanding: Money
    /// A Loan (they owe the user) or a Debt (the user owes them).
    let kind: LoanOrDebtKind
    /// The phone number of the Person it is with, when they have one.
    var phone: String?
    var arrival = ReminderArrival.onItsDay

    var textThem: TextThemPayload? {
        TextThemPayload(
            person: person, personName: withName, phone: phone, outstanding: outstanding, youOwe: kind == .debt
        )
    }

    /// "Loan reminder" or "Debt reminder".
    var title: String {
        switch kind {
        case .loan: String(localized: Strings.DebtsLoans.loanReminder)
        case .debt: String(localized: Strings.DebtsLoans.debtReminder)
        }
    }

    /// Who owes whom, and how much is outstanding.
    var body: String {
        let amount = outstanding.formatted()
        return switch kind {
        case .loan: String(localized: Strings.DebtsLoans.owesYou(withName, amount))
        case .debt: String(localized: Strings.DebtsLoans.youOwe(withName, amount))
        }
    }
}

extension DebtsAndLoans: ReminderSource {
    static func reminderDay(of loanOrDebt: LoanOrDebt) -> CalendarDay? { loanOrDebt.openReminderDay }

    static func reminder(for loanOrDebt: LoanOrDebt, on day: CalendarDay) -> DebtReminder {
        let person = loanOrDebt.person
        return DebtReminder(
            original: loanOrDebt.original.persistentModelID, day: day, person: person?.persistentModelID,
            withName: person?.name ?? "", outstanding: loanOrDebt.outstanding, kind: loanOrDebt.kind,
            phone: person?.phone
        )
    }
}

extension LoanOrDebt: ListedWithReminder {
    var openReminderDay: CalendarDay? { isSettled ? nil : original.reminderDay }
}

extension Transaction: RemindedRecord {
    /// Only a Loan or Debt takes a reminder.
    func checkTakesReminder() throws {
        guard isLoanOrDebt else { throw DebtLoanRuleError.notALoanOrDebt }
    }
}
