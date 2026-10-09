import Foundation
import SwiftData

/// One dated movement of money into or out of one wallet, filed under one category.
@Model
final class Transaction {
    /// Signed effect on the wallet in cents: positive adds money, negative takes it away.
    var amountCents: Int = 0
    /// The ``CalendarDay`` as `yyyymmdd`.
    var dayRaw: Int = 0
    var note: String = ""
    /// The person the transaction involved ("With").
    var withName: String = ""
    var eventName: String = ""
    var isExcludedFromReport: Bool = false
    /// Transactions sharing a link are related: the two halves of a transfer, or a Loan and its Debt Collections.
    var linkID: UUID?
    /// When the transaction was entered; orders transactions within a day.
    var createdAt: Date = Date.now

    var wallet: Wallet?
    var category: Category?
    var card: Card?

    init(
        amount: Money,
        day: CalendarDay,
        wallet: Wallet?,
        category: Category?,
        card: Card? = nil,
        note: String = ""
    ) {
        self.amountCents = amount.cents
        self.dayRaw = day.rawValue
        self.wallet = wallet
        self.category = category
        self.card = card
        self.note = note
    }

    var amount: Money { Money(cents: amountCents, currencyCode: wallet?.currencyCode ?? Money.defaultCurrencyCode) }

    var day: CalendarDay {
        get { CalendarDay(rawValue: dayRaw) }
        set { dayRaw = newValue.rawValue }
    }
}
