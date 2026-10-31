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
    /// Only a forgiven Loan or Debt can be un-forgiven.
    case notForgiven
    /// A forgiven Loan or Debt keeps its amount, wallet and category until it is un-forgiven.
    case lockedByForgiveness
}

extension DebtLoanRuleError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notALoanOrDebt:
            String(localized: Strings.DebtsLoans.notALoanOrDebt)
        case .alreadySettled:
            String(localized: Strings.DebtsLoans.nothingOutstanding)
        case .categoryDoesNotMatch:
            String(localized: Strings.DebtsLoans.overpaymentCategoryType)
        case .paymentDoesNotMatch:
            String(localized: Strings.DebtsLoans.wrongPaymentCategory)
        case .lockedByPayments:
            String(localized: Strings.DebtsLoans.paymentsLock)
        case .amountBelowPaid:
            String(localized: Strings.DebtsLoans.amountBelowPaid)
        case .notForgiven:
            String(localized: Strings.DebtsLoans.notForgiven)
        case .lockedByForgiveness:
            String(localized: Strings.DebtsLoans.unforgiveFirst)
        }
    }
}
