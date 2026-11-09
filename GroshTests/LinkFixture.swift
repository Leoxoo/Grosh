import Foundation
@testable import Grosh

/// The transaction each test link was first given to, by the id the test names it with.
@MainActor private var testLinks: [UUID: Transaction] = [:]

extension Transaction {
    /// Puts the transaction on the link a test names `id`, of `kind`: the first transaction given an `id` makes the
    /// link, the rest join it, as the rules that make links do (ADR-0012). `nil` leaves it on none.
    @MainActor func joinTestLink(_ id: UUID?, as kind: LinkKind) {
        guard let id else { return }
        if let first = testLinks[id] {
            join(first, as: kind)
        } else {
            Transaction.link([self], as: kind)
            testLinks[id] = self
        }
    }
}
