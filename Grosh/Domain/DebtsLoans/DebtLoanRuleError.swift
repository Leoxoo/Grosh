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
        }
    }
}
