import Foundation
import SwiftData

extension Transaction {
    /// The transactions linked to this one, shown as its Related transactions: the other half of a transfer,
    /// or a Loan or Debt and its payments. Listed newest first.
    func related(in context: ModelContext) throws -> [Transaction] {
        guard let link = linkID else { return [] }
        let linked = FetchDescriptor<Transaction>(predicate: #Predicate { $0.linkID == link })
        return try context.fetch(linked).filter { $0 != self }.inListOrder()
    }
}
