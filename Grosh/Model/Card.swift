import Foundation
import SwiftData

nonisolated enum CardKind: String, CaseIterable, Sendable {
    /// Spends straight from its wallet; has no statement.
    case debit
    /// Has a statement and is paid off in full.
    case credit
}

/// The payment card an expense was made with. Only a label: it never changes any balance.
@Model
final class Card {
    /// The SF Symbol every Card is drawn with.
    static let symbolName = "creditcard.fill"

    var name: String = ""
    var kindRaw: String = CardKind.credit.rawValue
    var colorName: String = PaletteColor.blue.rawValue
    var lastFourDigits: String?
    /// The day of the month (1–31) a Credit card's statement closes.
    var statementDay: Int?
    var isArchived: Bool = false
    var sortOrder: Int = 0

    var payingWallet: Wallet?

    @Relationship(deleteRule: .nullify, inverse: \Transaction.card)
    var transactions: [Transaction]? = []

    init(name: String, kind: CardKind, payingWallet: Wallet?, color: PaletteColor = .blue, sortOrder: Int = 0) {
        self.name = name
        self.kindRaw = kind.rawValue
        self.payingWallet = payingWallet
        self.color = color
        self.sortOrder = sortOrder
    }

    var kind: CardKind {
        get { CardKind(rawValue: kindRaw) ?? .credit }
        set { kindRaw = newValue.rawValue }
    }

    var color: PaletteColor {
        get { PaletteColor(storedName: colorName) }
        set { colorName = newValue.rawValue }
    }
}
