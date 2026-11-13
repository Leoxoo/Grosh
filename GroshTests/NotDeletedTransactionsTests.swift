import Foundation
import Observation
import os
import SwiftData
import Testing
@testable import Grosh

/// The transactions outside Recently Deleted that Home, the Transactions tab, search and Link Existing share: read once,
/// then kept in step with every save, so they always hold what `@Query(Transaction.notDeleted)` would.
@MainActor
@Suite(.namedInTheLog)
struct NotDeletedTransactionsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = container.mainContext.addWallet("Checking")
    }

    @discardableResult
    private func record(_ note: String, in wallet: Wallet? = nil) -> Transaction {
        context.record(-5_00, on: today, in: wallet ?? checking, note: note)
    }

    private var shared: NotDeletedTransactions.Store { .of(context) }

    /// The notes of the shared transactions, beside those a fresh read of the store gives.
    private func notes() throws -> (shared: Set<String>, fetched: Set<String>) {
        (Set(shared.transactions.map(\.note)), Set(try context.fetch(Transaction.notDeleted).map(\.note)))
    }

    @Test func theyStartAsEveryTransactionOutsideRecentlyDeleted() throws {
        record("coffee")
        record("rent").changeCounted { $0.deletedAt = .now }
        try context.save()

        #expect(try notes().shared == ["coffee"])
    }

    @Test func aTransactionJoinsOnceItIsSaved() throws {
        record("coffee")
        try context.save()
        _ = shared

        record("lunch")
        #expect(try notes().shared == ["coffee"])

        try context.save()
        let notes = try notes()
        #expect(notes.shared == ["coffee", "lunch"])
        #expect(notes.shared == notes.fetched)
    }

    @Test func aTransactionMovedToRecentlyDeletedLeavesAndComesBackWhenRestored() throws {
        let coffee = record("coffee")
        record("lunch")
        try context.save()
        _ = shared

        try [coffee].delete(.onlySelected)
        #expect(try notes().shared == ["lunch"])

        try coffee.restore()
        let notes = try notes()
        #expect(notes.shared == ["coffee", "lunch"])
        #expect(notes.shared == notes.fetched)
    }

    @Test func aTransactionDeletedForeverStaysOut() throws {
        let coffee = record("coffee")
        record("lunch")
        try context.save()
        _ = shared

        try [coffee].delete(.onlySelected)
        try coffee.deleteForever()

        let notes = try notes()
        #expect(notes.shared == ["lunch"])
        #expect(notes.shared == notes.fetched)
    }

    @Test func aWalletsTransactionsLeaveWithItAndComeBackWithIt() throws {
        let savings = context.addWallet("Savings")
        record("coffee")
        record("interest", in: savings)
        try context.save()
        _ = shared

        try savings.delete(today: TestStore.today)
        #expect(try notes().shared == ["coffee"])

        try savings.restore(today: today)
        #expect(try notes().shared == ["coffee", "interest"])

        try savings.delete(today: TestStore.today)
        try savings.deleteForever()
        let notes = try notes()
        #expect(notes.shared == ["coffee"])
        #expect(notes.shared == notes.fetched)
    }

    /// Performance contract (the 16k store, `docs/agents/architecture.md`): a screen showing them redraws for a change to
    /// a transaction through the transaction itself, so a save that brings none in and takes none out must not
    /// invalidate the whole list. The last line is the behaviour.
    @Test func editingATransactionKeepsTheListAndShowsTheEdit() throws {
        let coffee = record("coffee")
        try context.save()
        let store = shared
        // onChange is a Sendable closure, so the flag it sets is behind a lock.
        let listChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = store.transactions } onChange: { listChanged.withLock { $0 = true } }

        coffee.changeCounted { $0.amountCents = -7_50 }
        try context.save()

        #expect(!listChanged.withLock { $0 })
        #expect(store.transactions.map(\.amountCents) == [-7_50])
    }

    /// Balances add up the ledger entries, so a saved change to a transaction's wallet, day or amount is read into its
    /// entry, and the screens adding them up redraw.
    @Test func aSavedChangeToTheWalletDayOrAmountIsReadIntoTheLedger() throws {
        let savings = context.addWallet("Savings")
        let coffee = record("coffee")
        try context.save()
        let store = shared

        // onChange is a Sendable closure, so the flag it sets is behind a lock.
        let ledgerChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = store.entries } onChange: { ledgerChanged.withLock { $0 = true } }
        coffee.changeCounted { $0.amountCents = -7_50 }
        #expect(store.entries.map(\.netCents) == [-5_00])
        try context.save()
        #expect(ledgerChanged.withLock { $0 })
        #expect(store.entries.map(\.netCents) == [-7_50])

        coffee.changeCounted { $0.wallet = savings }
        coffee.changeCounted { $0.day = today.adding(days: -3) }
        try context.save()
        let balances = WalletBalances(store.entries, asOf: today)
        #expect(balances.balance(of: savings) == Money(cents: -7_50))
        #expect(balances.balance(of: checking) == Money(cents: 0))
        #expect(WalletBalances(store.entries, asOf: today.adding(days: -4)).balance(of: savings) == Money(cents: 0))
    }

    /// Performance contract (the 16k store): a saved change that moves no balance must not make every screen adding up
    /// the ledger redraw.
    @Test func aSavedChangeToAnythingElseLeavesTheLedgerAsItWas() throws {
        let coffee = record("coffee")
        try context.save()
        let store = shared
        // onChange is a Sendable closure, so the flag it sets is behind a lock.
        let ledgerChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = store.entries } onChange: { ledgerChanged.withLock { $0 = true } }

        coffee.note = "espresso"
        try context.save()

        #expect(!ledgerChanged.withLock { $0 })
    }

    @Test func eachContextHasItsOwn() throws {
        record("coffee")
        try context.save()
        let other = try GroshStore.makeContainer(inMemory: true)

        #expect(NotDeletedTransactions.Store.of(context) === shared)
        #expect(NotDeletedTransactions.Store.of(other.mainContext).transactions.isEmpty)
    }
}
