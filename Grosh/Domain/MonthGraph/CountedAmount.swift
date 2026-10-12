/// One of the Month graph's two cards: Spent, for money going out, or Income, for money coming in.
nonisolated enum SpentOrIncome: CaseIterable, Sendable {
    case spent
    case income
}

/// An amount that counts on the Month graph: toward Spent or Income, on the day it counts.
struct CountedAmount {
    let side: SpentOrIncome
    let day: CalendarDay
    /// What it adds to its card's total. A refund takes away from Spent, so it is below zero there.
    let amount: Money
}

extension CountedAmount {
    /// `amount`, as it moves a wallet, filed under `category` on `day`. Under an Expense category it counts toward Spent
    /// turned around, so money going out adds to Spent and a refund takes away from it; under an Income category it
    /// counts toward Income as it is. Under any other category, a Debt/Loan one or one of the app's own such as
    /// Starting balance, it counts toward neither.
    fileprivate init?(_ amount: Money, filedUnder category: Category?, on day: CalendarDay) {
        switch category?.type {
        case .expense:
            self.init(side: .spent, day: day, amount: Money(cents: -amount.cents, currencyCode: amount.currencyCode))
        case .income:
            self.init(side: .income, day: day, amount: amount)
        default:
            return nil
        }
    }
}

extension Transaction {
    /// What the transaction counts on the Month graph, or `nil` when it counts toward neither card. Only the wallets
    /// counted in the Total count, and nothing in Recently Deleted does.
    ///
    /// A forgiven Loan or Debt counts what was forgiven, on the day it was forgiven and under the category that amount
    /// is filed under (ADR-0004). Its own Exclude from report flag doesn't matter: a Loan or Debt starts excluded, and is
    /// never income or spending itself. Any other transaction counts its own amount by its category, as long as it
    /// counts in the report.
    var countedAmount: CountedAmount? {
        guard WalletSelection.total.includes(self), !isInRecentlyDeleted else { return nil }
        if let forgiveness {
            return CountedAmount(forgiveness.reportAmount, filedUnder: forgiveness.category, on: forgiveness.day)
        }
        return countsInReport ? CountedAmount(amount, filedUnder: category, on: day) : nil
    }
}
