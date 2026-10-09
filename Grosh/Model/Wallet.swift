import Foundation
import SwiftData

/// A place the user's money is held. Its balance is always derived from its transactions, never stored.
@Model
final class Wallet {
    var name: String = ""
    var symbolName: String = "wallet.bifold.fill"
    var colorName: String = PaletteColor.green.rawValue
    var currencyCode: String = "USD"
    var includeInTotal: Bool = true
    var isArchived: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date.now

    @Relationship(inverse: \Transaction.wallet)
    var transactions: [Transaction]? = []

    @Relationship(deleteRule: .nullify, inverse: \Card.payingWallet)
    var cards: [Card]? = []

    init(name: String, symbolName: String = "wallet.bifold.fill", color: PaletteColor = .green, sortOrder: Int = 0) {
        self.name = name
        self.symbolName = symbolName
        self.colorName = color.rawValue
        self.sortOrder = sortOrder
    }
}
