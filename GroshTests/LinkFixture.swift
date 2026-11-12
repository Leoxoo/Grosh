import Foundation
@testable import Grosh

/// The links one test makes in its store, named by ids of the test's own. A suite holds one beside its store, so a new
/// one comes with each test and its transactions go with the store.
@MainActor
final class TestLinks {
    /// The transaction each link was first given to, by the id the test names it with.
    private var first: [UUID: Transaction] = [:]

    /// Puts `transaction` on the link the test names `id`, of `kind`: the first transaction given an `id` makes the
    /// link, the rest join it, as the rules that make links do (ADR-0012). `nil` leaves it on none.
    func put(_ transaction: Transaction, on id: UUID?, as kind: LinkKind) {
        guard let id else { return }
        if let first = first[id] {
            transaction.join(first, as: kind)
        } else {
            Transaction.link([transaction], as: kind)
            first[id] = transaction
        }
    }
}
