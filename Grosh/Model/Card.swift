import Foundation
import SwiftData

nonisolated enum CardKind: String, Sendable {
    /// Spends straight from its wallet, no statement.
    case debit
    /// Has a statement and is paid off in full.
    case credit
}

/// The payment card an expense was made with. Only a label: it never changes any wallet's balance.
@Model
final class Card {
    var name: String = ""
    var kindValue: String = CardKind.debit.rawValue
    var colorName: String = "blue"
    var lastFourDigits: String?
    /// The day of the month a Credit card's statement closes (1–31).
    var statementDay: Int?
    var isArchived: Bool = false
    var sortOrder: Int = 0

    var payingWallet: Wallet?

    @Relationship(inverse: \Transaction.card)
    var transactions: [Transaction]? = []

    init(name: String, kind: CardKind, payingWallet: Wallet?) {
        self.name = name
        self.kindValue = kind.rawValue
        self.payingWallet = payingWallet
    }

    var kind: CardKind {
        get { CardKind(rawValue: kindValue) ?? .debit }
        set { kindValue = newValue.rawValue }
    }
}
