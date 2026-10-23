import Foundation
import SwiftData
import SwiftUI

/// Every transaction outside Recently Deleted (``Transaction/notDeleted``), as `@Query(Transaction.notDeleted)` gives
/// them, for the screens that need them all: Home's balances, the Transactions tab, search and Link Existing. Its
/// projected value holds their ``LedgerEntry``s, for adding balances up.
///
/// They are read from the store once for the view's model context and then kept in step with each of its saves: a
/// transaction saved new or brought back from Recently Deleted joins them, and one moved there or removed for good leaves.
/// A query reads all of them again after every save instead, once for each screen showing them, and reading ~16,000
/// takes a quarter of a second. A change to a transaction's own values, its note say, reaches the screens as it always
/// does, through the transaction itself; its ledger entry is read again when the change is saved.
@propertyWrapper
struct NotDeletedTransactions: DynamicProperty {
    @Environment(\.modelContext) private var context

    var wrappedValue: [Transaction] { Store.of(context).transactions }

    var projectedValue: [LedgerEntry] { Store.of(context).entries }
}

extension NotDeletedTransactions {
    /// The transactions of one model context, read once and kept in step with its saves.
    @Observable
    final class Store {
        /// In no particular order, as a query without a sort gives them. Replaced only when one joins or leaves.
        private(set) var transactions: [Transaction]
        /// The ledger entry of each of the transactions, in the same order. Replaced too when a save changes the wallet,
        /// day or amount of one of them.
        private(set) var entries: [LedgerEntry]
        /// Where each transaction is in both lists.
        @ObservationIgnored private var positions: [PersistentIdentifier: Int]
        @ObservationIgnored private weak var context: ModelContext?
        @ObservationIgnored nonisolated(unsafe) private var saves: (any NSObjectProtocol)?

        /// The context's store, made the first time a screen asks for it.
        static func of(_ context: ModelContext) -> Store {
            // A store whose context is gone is dropped, and so is one left by a context whose memory is used again.
            stores = stores.filter { $0.value.context != nil }
            if let store = stores[ObjectIdentifier(context)], store.context === context { return store }
            let store = Store(context)
            stores[ObjectIdentifier(context)] = store
            return store
        }

        private static var stores: [ObjectIdentifier: Store] = [:]

        private init(_ context: ModelContext) {
            self.context = context
            let transactions = Log.store.attempt("Reading every transaction") {
                try context.fetch(Transaction.notDeleted)
            } ?? []
            self.transactions = transactions
            entries = transactions.map { LedgerEntry($0) }
            positions = Self.positions(of: transactions)
            saves = NotificationCenter.default.addObserver(
                forName: ModelContext.didSave, object: context, queue: nil
            ) { [weak self] notification in
                let changes = Changes(notification)
                MainActor.assumeIsolated { self?.apply(changes) }
            }
        }

        deinit {
            if let saves { NotificationCenter.default.removeObserver(saves) }
        }

        private static func positions(of transactions: [Transaction]) -> [PersistentIdentifier: Int] {
            Dictionary(uniqueKeysWithValues: transactions.enumerated().map { ($1.persistentModelID, $0) })
        }

        /// The models a save inserted, updated and deleted, by their identifiers.
        nonisolated private struct Changes: @unchecked Sendable {
            let changed: [PersistentIdentifier]
            let deleted: Set<PersistentIdentifier>

            init(_ notification: Notification) {
                func identifiers(_ key: ModelContext.NotificationKey) -> [PersistentIdentifier] {
                    notification.userInfo?[key.rawValue] as? [PersistentIdentifier] ?? []
                }
                changed = identifiers(.insertedIdentifiers) + identifiers(.updatedIdentifiers)
                deleted = Set(identifiers(.deletedIdentifiers))
            }
        }

        private static let entityName = Schema.entityName(for: Transaction.self)

        /// Takes in what a save changed: each transaction saved outside Recently Deleted is among them, with its ledger
        /// entry read again, and each moved there or deleted isn't.
        private func apply(_ changes: Changes) {
            guard let context else { return }
            var leaving = changes.deleted.filter { positions[$0] != nil }
            var joining: [Transaction] = []
            var entries = self.entries
            var entriesChanged = false
            for identifier in changes.changed where identifier.entityName == Self.entityName {
                guard let transaction = context.model(for: identifier) as? Transaction else { continue }
                let position = positions[identifier]
                if transaction.deletedAt != nil {
                    if position != nil { leaving.insert(identifier) }
                } else if let position {
                    let entry = LedgerEntry(transaction)
                    if !entry.hasSameFigures(as: entries[position]) {
                        entries[position] = entry
                        entriesChanged = true
                    }
                } else {
                    joining.append(transaction)
                }
            }
            if leaving.isEmpty && joining.isEmpty {
                if entriesChanged { self.entries = entries }
                return
            }
            var transactions = self.transactions
            if !leaving.isEmpty {
                let kept = transactions.indices.filter { !leaving.contains(transactions[$0].persistentModelID) }
                transactions = kept.map { transactions[$0] }
                entries = kept.map { entries[$0] }
            }
            transactions += joining
            entries += joining.map { LedgerEntry($0) }
            positions = Self.positions(of: transactions)
            self.transactions = transactions
            self.entries = entries
        }
    }
}
