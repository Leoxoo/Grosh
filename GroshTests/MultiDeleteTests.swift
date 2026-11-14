import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Select multiple → Delete in the Transactions tab's "…" menu. It goes through the same delete scopes as deleting
/// one transaction, so a link is never broken silently.
@MainActor
@Suite(.namedInTheLog)
struct MultiDeleteTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet
    private let savings: Wallet
    private let links = TestLinks()

    init() throws {
        container = try TestStore.makeContainer()
        checking = container.mainContext.addWallet("Checking")
        savings = container.mainContext.addWallet("Savings")
    }

    @discardableResult
    private func record(_ note: String, _ cents: Int, in wallet: Wallet, link: UUID? = nil) -> Transaction {
        let transaction = context.record(cents, on: today, in: wallet, note: note)
        links.put(transaction, on: link, as: .transfer)
        return transaction
    }

    @Test func aSelectionWithNothingRelatedIsSimplyDeleted() throws {
        record("salary", 100_00, in: checking)
        let selection = [record("coffee", -4_50, in: checking), record("lunch", -12_00, in: checking)]

        #expect(try selection.deleteScopes() == [.onlySelected])
        try selection.delete(.onlySelected)

        #expect(try context.notDeletedNotes() == ["salary"])
        #expect(walletBalance(checking, asOf: today) == Money(cents: 100_00))
    }

    @Test func selectingBothHalvesOfATransferBreaksNoLinkSoNothingMoreIsAsked() throws {
        let transfer = UUID()
        let selection = [
            record("to savings", -500_00, in: checking, link: transfer),
            record("from checking", 500_00, in: savings, link: transfer),
        ]

        #expect(try selection.related().isEmpty)
        #expect(try selection.deleteScopes() == [.onlySelected])
    }

    @Test func aSelectionHoldingOneHalfOfATransferAsksWhetherToDeleteTheOtherHalfToo() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        let incoming = record("from checking", 500_00, in: savings, link: transfer)
        let selection = [outgoing, record("coffee", -4_50, in: checking)]

        #expect(try selection.related() == [incoming])
        #expect(try selection.deleteScopes() == [.withRelated, .onlySelected])
    }

    @Test func deletingWithRelatedAlsoDeletesTheLinkedTransactionsLeftOutOfTheSelection() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)
        let coffee = record("coffee", -4_50, in: checking)
        record("another transfer", -10_00, in: checking, link: UUID())

        try [outgoing, coffee].delete(.withRelated)

        #expect(try context.notDeletedNotes() == ["another transfer"])
        #expect(walletBalance(savings, asOf: today) == Money(cents: 0))
    }

    @Test func deletingOnlyTheSelectionKeepsTheLinkedTransactionsLeftOutOfIt() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        record("from checking", 500_00, in: savings, link: transfer)
        let coffee = record("coffee", -4_50, in: checking)

        try [outgoing, coffee].delete(.onlySelected)

        #expect(try context.notDeletedNotes() == ["from checking"])
    }

    @Test func linkedPaymentsLeftOutOfTheSelectionAreEachCountedOnce() throws {
        let loan = UUID()
        let lent = record("lent to Pasha", -100_00, in: checking, link: loan)
        let firstPayment = record("Pasha paid 60", 60_00, in: checking, link: loan)
        let secondPayment = record("Pasha paid 40", 40_00, in: checking, link: loan)

        #expect(try [firstPayment, secondPayment].related() == [lent])

        try [firstPayment, secondPayment].delete(.withRelated)

        #expect(try context.notDeletedNotes().isEmpty)
    }

    // MARK: What the user is asked

    @Test func aSelectionWithNothingRelatedIsConfirmedWithItsCount() {
        #expect(TransactionDeleteScope.onlySelected.buttonTitle(selectedCount: 3, relatedCount: 0) == "Delete 3 Transactions")
    }

    @Test func aSelectionWithRelatedTransactionsOffersAllOfThemOrOnlyTheSelectedOnes() {
        #expect(TransactionDeleteScope.withRelated.buttonTitle(selectedCount: 3, relatedCount: 1) == "Delete All 4")
        #expect(TransactionDeleteScope.onlySelected.buttonTitle(selectedCount: 3, relatedCount: 1) == "Only These 3")
    }

    @Test func selectingOneTransactionAsksWhatDeletingItFromItsDetailAsks() {
        #expect(TransactionDeleteScope.withRelated.buttonTitle(selectedCount: 1, relatedCount: 1) == "Delete Both")
        #expect(TransactionDeleteScope.onlySelected.buttonTitle(selectedCount: 1, relatedCount: 1) == "Only This One")
        #expect(TransactionDeleteScope.onlySelected.buttonTitle(selectedCount: 1, relatedCount: 0) == "Delete Transaction")
    }
}
