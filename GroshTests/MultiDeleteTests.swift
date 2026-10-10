import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Select multiple → Delete in the Transactions tab's "…" menu. It goes through the same delete scopes as deleting
/// one transaction, so a link is never broken silently.
@MainActor
struct MultiDeleteTests {
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
    private func record(_ note: String, _ cents: Int, in wallet: Wallet, link: UUID? = nil) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: today, wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = wallet
        transaction.linkID = link
        return transaction
    }

    private func notes() throws -> Set<String> {
        Set(try context.fetch(FetchDescriptor<Transaction>()).map(\.note))
    }

    @Test func aSelectionWithNothingRelatedIsSimplyDeleted() throws {
        record("salary", 100_00, in: checking)
        let selection = [record("coffee", -4_50, in: checking), record("lunch", -12_00, in: checking)]

        #expect(try selection.deleteScopes(in: context) == [.onlyThisOne])
        try selection.delete(.onlyThisOne, in: context)

        #expect(try notes() == ["salary"])
        #expect(checking.balance(asOf: today) == Money(cents: 100_00))
    }

    @Test func selectingBothHalvesOfATransferBreaksNoLinkSoNothingMoreIsAsked() throws {
        let transfer = UUID()
        let selection = [
            record("to savings", -500_00, in: checking, link: transfer),
            record("from checking", 500_00, in: savings, link: transfer),
        ]

        #expect(try selection.related(in: context).isEmpty)
        #expect(try selection.deleteScopes(in: context) == [.onlyThisOne])
    }

    @Test func aSelectionHoldingOneHalfOfATransferAsksWhetherToDeleteTheOtherHalfToo() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        let incoming = record("from checking", 500_00, in: savings, link: transfer)
        let selection = [outgoing, record("coffee", -4_50, in: checking)]

        #expect(try selection.related(in: context) == [incoming])
        #expect(try selection.deleteScopes(in: context) == [.withRelated, .onlyThisOne])
    }

    @Test func deletingWithRelatedAlsoDeletesTheLinkedTransactionsLeftOutOfTheSelection() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)
        let coffee = record("coffee", -4_50, in: checking)
        record("another transfer", -10_00, in: checking, link: UUID())

        try [outgoing, coffee].delete(.withRelated, in: context)

        #expect(try notes() == ["another transfer"])
        #expect(savings.balance(asOf: today) == Money(cents: 0))
    }

    @Test func deletingOnlyTheSelectionKeepsTheLinkedTransactionsLeftOutOfIt() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)
        let coffee = record("coffee", -4_50, in: checking)

        try [outgoing, coffee].delete(.onlyThisOne, in: context)

        #expect(try notes() == ["from checking"])
    }

    @Test func linkedPaymentsLeftOutOfTheSelectionAreEachCountedOnce() throws {
        let loan = UUID()
        let lent = record("lent to Pasha", -100_00, in: checking, link: loan)
        let firstPayment = record("Pasha paid 60", 60_00, in: checking, link: loan)
        let secondPayment = record("Pasha paid 40", 40_00, in: checking, link: loan)

        #expect(try [firstPayment, secondPayment].related(in: context) == [lent])

        try [firstPayment, secondPayment].delete(.withRelated, in: context)

        #expect(try notes().isEmpty)
    }

    // MARK: What the user is asked

    @Test func aSelectionWithNothingRelatedIsConfirmedWithItsCount() {
        #expect(TransactionDeleteScope.onlyThisOne.buttonTitle(selectedCount: 3, relatedCount: 0) == "Delete 3 Transactions")
    }

    @Test func aSelectionWithRelatedTransactionsOffersAllOfThemOrOnlyTheSelectedOnes() {
        #expect(TransactionDeleteScope.withRelated.buttonTitle(selectedCount: 3, relatedCount: 1) == "Delete All 4")
        #expect(TransactionDeleteScope.onlyThisOne.buttonTitle(selectedCount: 3, relatedCount: 1) == "Only These 3")
    }

    @Test func selectingOneTransactionAsksWhatDeletingItFromItsDetailAsks() {
        #expect(TransactionDeleteScope.withRelated.buttonTitle(selectedCount: 1, relatedCount: 1) == "Delete Both")
        #expect(TransactionDeleteScope.onlyThisOne.buttonTitle(selectedCount: 1, relatedCount: 1) == "Only This One")
        #expect(TransactionDeleteScope.onlyThisOne.buttonTitle(selectedCount: 1, relatedCount: 0) == "Delete Transaction")
    }
}
