import Foundation

/// Which way an amount moves its wallet: money coming in, money going out, or neither (zero, or a Debt/Loan before
/// Loan or Debt is picked). An amount typed positive on the Keypad is shown in the direction its category gives it.
nonisolated enum MoneyDirection: Hashable, Sendable {
    case moneyIn
    case moneyOut
    case neither

    /// The direction of a sign or an amount in cents: above zero comes in, below zero goes out.
    init(sign: Int) {
        self = sign > 0 ? .moneyIn : sign < 0 ? .moneyOut : .neither
    }

    /// The direction a transaction filed under `category` moves its wallet (``Category/sign``), or ``neither`` before
    /// a category is chosen.
    init(category: Category?) {
        self.init(sign: category?.sign ?? 0)
    }
}

nonisolated extension Money {
    /// Whether the amount comes in, goes out, or is zero.
    var direction: MoneyDirection { MoneyDirection(sign: cents) }
}

nonisolated extension TransactionDraft {
    /// The way the typed amount moves the wallet (``sign``).
    var direction: MoneyDirection { MoneyDirection(sign: sign) }
}

nonisolated extension LoanOrDebtKind {
    /// The way a payment moves the wallet (``paymentSign``): a Debt Collection comes in, a Repayment goes out.
    var paymentDirection: MoneyDirection { MoneyDirection(sign: paymentSign) }
}
