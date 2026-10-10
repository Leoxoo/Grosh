import Foundation

/// Why a payment or forgive on a Loan or Debt can't be recorded.
nonisolated enum DebtLoanRuleError: Error, Equatable {
    /// Only a Loan or a Debt is paid back or forgiven.
    case notALoanOrDebt
    /// Nothing is outstanding any more.
    case alreadySettled
    /// What is paid beyond a Loan, or forgiven on a Debt, is filed under an Income category; what is paid beyond a
    /// Debt, or forgiven on a Loan, under an Expense category.
    case categoryDoesNotMatch
    /// A Loan is paid with Debt Collections and a Debt with Repayments.
    case paymentDoesNotMatch
    /// A Loan or Debt with payments keeps the wallet and category they were recorded against.
    case lockedByPayments
    /// A Loan or Debt can't be for less than what has been collected or repaid on it.
    case amountBelowPaid
}

extension DebtLoanRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notALoanOrDebt:
            String(localized: "Only a Loan or a Debt can be paid back or forgiven.")
        case .alreadySettled:
            String(localized: "Nothing is outstanding any more.")
        case .categoryDoesNotMatch:
            String(localized: "Choose an Income category for money that comes in, or an Expense category for money that goes out.")
        case .paymentDoesNotMatch:
            String(localized: "A Loan is paid back with Debt Collections, and a Debt with Repayments.")
        case .lockedByPayments:
            String(localized: "Its payments keep this Loan or Debt in its wallet and category.")
        case .amountBelowPaid:
            String(localized: "The amount can't be less than what has already been paid back.")
        }
    }
}
