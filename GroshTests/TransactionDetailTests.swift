import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The transaction detail: its Related transactions, whether it can be edited, and deleting it.
@MainActor
struct TransactionDetailTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet
    private let savings: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = Wallet(name: "Checking")
        savings = Wallet(name: "Savings")
        container.mainContext.insert(checking)
        container.mainContext.insert(savings)
    }

    @discardableResult
    private func record(
        _ note: String, _ cents: Int, in wallet: Wallet, link: UUID? = nil, enteredAt seconds: Double = 0
    ) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: today, wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = wallet
        transaction.linkID = link
        transaction.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
        return transaction
    }

    private func notes() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.note))
    }

    // MARK: Related transactions

    @Test func aTransactionWithoutALinkHasNoRelatedTransactions() throws {
        let coffee = record("coffee", -4_50, in: checking)
        record("lunch", -12_00, in: checking)

        #expect(try coffee.related(in: context).isEmpty)
    }

    @Test func transactionsSharingALinkListEachOtherButNotThemselves() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer, enteredAt: 1)
        let incoming = record("from checking", 500_00, in: savings, link: transfer, enteredAt: 2)
        record("another transfer", -10_00, in: checking, link: UUID())

        #expect(try outgoing.related(in: context) == [incoming])
        #expect(try incoming.related(in: context) == [outgoing])
    }

    // MARK: Edit and Duplicate

    @Test func aStartingBalanceCanBeNeitherEditedNorDuplicatedInTheAddSheet() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let wallet = try Wallet.create(
            name: "Credit line", startingBalance: Money(cents: -250_00), on: today, in: context
        )
        let startingBalance = try #require(wallet.transactions?.first)

        #expect(!startingBalance.isEditableInAddSheet)
    }

    @Test func anOrdinaryTransactionCanBeEditedAndDuplicated() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let cafe = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Café" })
        let coffee = record("coffee", -4_50, in: checking)
        coffee.category = cafe

        #expect(coffee.isEditableInAddSheet)
    }

    // MARK: Deleting

    @Test func deletingATransactionTakesItOutOfItsWalletsBalance() throws {
        record("salary", 100_00, in: checking)
        let coffee = record("coffee", -4_50, in: checking)

        try coffee.delete(.onlyThisOne, in: context)

        #expect(try notes() == ["salary"])
        #expect(checking.balance(asOf: today) == Money(cents: 100_00))
    }

    @Test func deletingOnlyThisOneKeepsTheRelatedTransactions() throws {
        let loan = UUID()
        let lent = record("lent to Pasha", -100_00, in: checking, link: loan)
        record("Pasha paid 60", 60_00, in: checking, link: loan)
        record("Pasha paid 40", 40_00, in: checking, link: loan)

        try lent.delete(.onlyThisOne, in: context)

        #expect(try notes() == ["Pasha paid 60", "Pasha paid 40"])
    }

    @Test func deletingWithRelatedDeletesEveryLinkedTransaction() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)
        record("coffee", -4_50, in: checking)
        record("another transfer", -10_00, in: checking, link: UUID())

        try outgoing.delete(.withRelated, in: context)

        #expect(try notes() == ["coffee", "another transfer"])
        #expect(savings.balance(asOf: today) == Money(cents: 0))
    }

    @Test func aTransactionWithNothingRelatedIsDeletedOnItsOwn() throws {
        let coffee = record("coffee", -4_50, in: checking)

        #expect(try coffee.deleteScopes(in: context) == [.onlyThisOne])
    }

    @Test func aTransactionWithRelatedTransactionsOffersToDeleteThemToo() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)

        #expect(try outgoing.deleteScopes(in: context) == [.withRelated, .onlyThisOne])
    }
}
