import SwiftUI

/// The words and colors that differ between a Loan and a Debt on screen and in notifications.
extension LoanOrDebtKind {
    /// "Loan" or "Debt".
    var name: LocalizedStringKey {
        switch self {
        case .loan: "Loan"
        case .debt: "Debt"
        }
    }

    /// The With row's label: who the money was lent to or borrowed from.
    var withTitle: LocalizedStringKey {
        switch self {
        case .loan: "Lent To"
        case .debt: "Borrowed From"
        }
    }

    /// What is outstanding: green for money coming back, red for money owed.
    var outstandingColor: Color {
        switch self {
        case .loan: .green
        case .debt: .red
        }
    }

    /// "Loan · May 27, 2026" or "Debt · May 27, 2026", for the day it was lent or borrowed.
    func summary(lentOrBorrowedOn day: String) -> String {
        switch self {
        case .loan: String(localized: "Loan · \(day)")
        case .debt: String(localized: "Debt · \(day)")
        }
    }

    /// The detail's Loan or Debt section, while something is outstanding.
    var paymentsFooter: LocalizedStringKey {
        switch self {
        case .loan: "Payments are recorded as Debt Collections. The Loan itself never changes."
        case .debt: "Payments are recorded as Repayments. The Debt itself never changes."
        }
    }

    /// Record Payment's payment section.
    var recordPaymentFooter: LocalizedStringKey {
        switch self {
        case .loan:
            "Recorded as a Debt Collection in the Loan's wallet, excluded from report. The Loan itself doesn't change."
        case .debt:
            "Recorded as a Repayment from the Debt's wallet, excluded from report. The Debt itself doesn't change."
        }
    }

    /// Record Payment's section for what is paid above the outstanding amount.
    var overpaymentFooter: LocalizedStringKey {
        switch self {
        case .loan: "What's paid above the outstanding amount is recorded as income and counts in reports."
        case .debt: "What's paid above the outstanding amount is recorded as an expense and counts in reports."
        }
    }

    /// Forgive the Rest's form.
    var forgiveFooter: LocalizedStringKey {
        switch self {
        case .loan:
            "Settles the Loan with a Debt Collection and an expense of the same amount, so no balance changes. The expense counts in reports."
        case .debt:
            "Settles the Debt with a Repayment and an income of the same amount, so no balance changes. The income counts in reports."
        }
    }
}

extension DebtReminder {
    /// "Loan reminder" or "Debt reminder".
    var title: String {
        switch kind {
        case .loan: String(localized: "Loan reminder")
        case .debt: String(localized: "Debt reminder")
        }
    }

    /// Who owes whom, and how much is outstanding.
    var body: String {
        let amount = outstanding.formatted()
        return switch kind {
        case .loan: String(localized: "\(withName) owes you \(amount).")
        case .debt: String(localized: "You owe \(withName) \(amount).")
        }
    }
}
