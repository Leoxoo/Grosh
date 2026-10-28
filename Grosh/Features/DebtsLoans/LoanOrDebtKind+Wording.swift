import SwiftUI

/// The words that differ between a Loan and a Debt on screen and in notifications.
extension LoanOrDebtKind {
    /// "Loan" or "Debt".
    var name: LocalizedStringResource {
        switch self {
        case .loan: Strings.DebtsLoans.loan
        case .debt: Strings.DebtsLoans.debt
        }
    }

    /// The With row's label: who the money was lent to or borrowed from.
    var withTitle: LocalizedStringResource {
        switch self {
        case .loan: Strings.DebtsLoans.lentTo
        case .debt: Strings.DebtsLoans.borrowedFrom
        }
    }

    /// "Loan · May 27, 2026" or "Debt · May 27, 2026", for the day it was lent or borrowed.
    func summary(lentOrBorrowedOn day: String) -> String {
        switch self {
        case .loan: String(localized: Strings.DebtsLoans.loanOn(day))
        case .debt: String(localized: Strings.DebtsLoans.debtOn(day))
        }
    }

    /// The detail's Loan or Debt section, while something is outstanding.
    var paymentsFooter: LocalizedStringResource {
        switch self {
        case .loan: Strings.DebtsLoans.loanPaymentsFooter
        case .debt: Strings.DebtsLoans.debtPaymentsFooter
        }
    }

    /// Record Payment's payment section.
    var recordPaymentFooter: LocalizedStringResource {
        switch self {
        case .loan:
            Strings.DebtsLoans.loanRecordPaymentFooter
        case .debt:
            Strings.DebtsLoans.debtRecordPaymentFooter
        }
    }

    /// Record Payment's section for what is paid above the outstanding amount.
    var overpaymentFooter: LocalizedStringResource {
        switch self {
        case .loan: Strings.DebtsLoans.loanOverpaymentFooter
        case .debt: Strings.DebtsLoans.debtOverpaymentFooter
        }
    }

    /// Forgive the Rest's form.
    var forgiveFooter: LocalizedStringResource {
        switch self {
        case .loan:
            Strings.DebtsLoans.loanForgiveFooter
        case .debt:
            Strings.DebtsLoans.debtForgiveFooter
        }
    }

    /// The detail's Loan or Debt section, once forgiven.
    var forgivenFooter: LocalizedStringResource {
        switch self {
        case .loan: Strings.DebtsLoans.loanForgivenFooter
        case .debt: Strings.DebtsLoans.debtForgivenFooter
        }
    }

    /// The story of a Loan or Debt at a glance: "Lent $50 · Collected $30 · Forgiven $20", or "Borrowed $250 ·
    /// Repaid $200 · Forgiven $50 · Kept $50". Payments and the forgiven part are left out while there are none.
    func story(owed: Money, paid: Money, forgiven: Money?) -> String {
        var parts: [String] = []
        switch self {
        case .loan:
            parts.append(String(localized: Strings.DebtsLoans.lent(owed.formatted())))
            if paid.cents > 0 { parts.append(String(localized: Strings.DebtsLoans.collected(paid.formatted()))) }
            if let forgiven { parts.append(String(localized: Strings.DebtsLoans.forgivenAmount(forgiven.formatted()))) }
        case .debt:
            parts.append(String(localized: Strings.DebtsLoans.borrowed(owed.formatted())))
            if paid.cents > 0 { parts.append(String(localized: Strings.DebtsLoans.repaid(paid.formatted()))) }
            if let forgiven {
                parts.append(String(localized: Strings.DebtsLoans.forgivenAmount(forgiven.formatted())))
                parts.append(String(localized: Strings.DebtsLoans.kept(forgiven.formatted())))
            }
        }
        return parts.joined(separator: " · ")
    }
}

extension DebtReminder {
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
