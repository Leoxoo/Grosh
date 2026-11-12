import Foundation

/// What the Home bell lists as due on a day: the open Loans and Debts whose reminder day has come, the earliest first,
/// then the Owes me whose reminder day has come, then the estimated amounts waiting for their real figures.
struct DueReminders {
    let loansAndDebts: [LoanOrDebt]
    let expectations: [ExpectedReimbursement]
    let estimates: [Transaction]

    /// What is due on `today` among `transactions` (``DebtsAndLoans/records``), `expectations`
    /// (``ExpectedReimbursements/records``) and `estimates` (``EstimatedAmounts/records``).
    init(
        transactions: [Transaction], expectations: [ExpectedReimbursement], estimates: [Transaction],
        on today: CalendarDay
    ) {
        loansAndDebts = DebtsAndLoans(transactions).due(on: today)
        self.expectations = ExpectedReimbursements(expectations).due(on: today)
        self.estimates = EstimatedAmounts(estimates).due(on: today)
    }

    /// How many are due, which the bell's badge shows.
    var count: Int { loansAndDebts.count + expectations.count + estimates.count }

    var isEmpty: Bool { count == 0 }
}
