import Foundation
import SwiftData

/// One dated movement of money into or out of one wallet, filed under one category.
@Model
final class Transaction {
    /// Signed: positive adds to the wallet, negative subtracts from it. The user types a positive
    /// amount and the category type picks the sign; the stored value keeps the result.
    var amountCents: Int = 0
    /// The transaction's date as `CalendarDay.storedValue`.
    var dayValue: Int = 0
    /// When the user entered it. Within a day, the most recently entered transaction is on top.
    var enteredAt: Date = Date.now
    var note: String = ""
    /// The person the transaction involved: a name, not a contact.
    var with: String = ""
    /// Imported from MoneyLover; read-only in the app.
    var event: String?
    var isExcludedFromReport: Bool = false

    var wallet: Wallet?
    var category: Category?
    var card: Card?
    var link: TransactionLink?

    init(amount: Money, date: CalendarDay, wallet: Wallet?, category: Category?, note: String = "") {
        self.amountCents = amount.cents
        self.dayValue = date.storedValue
        self.wallet = wallet
        self.category = category
        self.note = note
    }

    var amount: Money {
        get { Money(cents: amountCents) }
        set { amountCents = newValue.cents }
    }

    var date: CalendarDay {
        get { CalendarDay(storedValue: dayValue) }
        set { dayValue = newValue.storedValue }
    }
}
