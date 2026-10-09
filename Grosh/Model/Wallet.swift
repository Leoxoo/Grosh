import Foundation
import SwiftData

/// A place the user's money is held: a checking or savings account, cash, or a brokerage.
@Model
final class Wallet {
    var name: String = ""
    var iconName: String = "wallet.bifold.fill"
    var colorName: String = "green"
    var currencyCode: String = "USD"
    var includeInTotal: Bool = true
    var isArchived: Bool = false
    /// Position in the user's drag-to-reorder order, used everywhere wallets are listed.
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \Transaction.wallet)
    var transactions: [Transaction]? = []

    @Relationship(inverse: \Card.payingWallet)
    var cards: [Card]? = []

    init(name: String) {
        self.name = name
    }
}
