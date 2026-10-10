import Foundation
import SwiftData

extension Transaction {
    /// The transactions linked to this one, shown as its Related transactions: the other half of a transfer,
    /// or a Loan or Debt and its payments. Listed newest first.
    func related(in context: ModelContext) throws -> [Transaction] {
        related(among: try context.fetch(linkedTransactions))
    }

    /// Every transaction sharing this one's link, this one included; nothing when it has no link. A list made from
    /// them stays current, since a transaction linked later (such as a payment on a Loan, which leaves the Loan
    /// itself unchanged) changes what this fetches.
    var linkedTransactions: FetchDescriptor<Transaction> {
        guard let link = linkID else { return FetchDescriptor(predicate: #Predicate { _ in false }) }
        return FetchDescriptor(predicate: #Predicate { $0.linkID == link })
    }

    /// The Related transactions among `linked` (what ``linkedTransactions`` fetches): all but this one, newest first.
    func related(among linked: [Transaction]) -> [Transaction] {
        linked.filter { $0 != self }.inListOrder()
    }
}
