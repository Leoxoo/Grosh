import Foundation
import SwiftData

/// Joins linked transactions, such as the two halves of a transfer or a Loan and its Debt Collections.
/// Each one shows the others as "Related transactions".
@Model
final class TransactionLink {
    @Relationship(inverse: \Transaction.link)
    var transactions: [Transaction]? = []

    init() {}
}
