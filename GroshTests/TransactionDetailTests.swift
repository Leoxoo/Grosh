import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The transaction detail: its Related transactions, whether it can be edited, and deleting it.
@MainActor
@Suite(.namedInTheLog)
struct TransactionDetailTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let checking: Wallet
    private let savings: Wallet
    private let links = TestLinks()

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = container.mainContext.addWallet("Checking")
        savings = container.mainContext.addWallet("Savings")
    }

    @discardableResult
    private func record(
        _ note: String, _ cents: Int, in wallet: Wallet, link: UUID? = nil, kind: LinkKind = .transfer,
        enteredAt seconds: Double = 0
    ) -> Transaction {
        let transaction = context.record(cents, on: today, in: wallet, note: note, enteredAt: seconds)
        links.put(transaction, on: link, as: kind)
        return transaction
    }

    // MARK: Related transactions

    @Test func aTransactionWithoutALinkHasNoRelatedTransactions() throws {
        let coffee = record("coffee", -4_50, in: checking)
        record("lunch", -12_00, in: checking)

        #expect(try coffee.related().isEmpty)
    }

    @Test func transactionsSharingALinkListEachOtherButNotThemselves() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer, enteredAt: 1)
        let incoming = record("from checking", 500_00, in: savings, link: transfer, enteredAt: 2)
        record("another transfer", -10_00, in: checking, link: UUID())

        #expect(try outgoing.related() == [incoming])
        #expect(try incoming.related() == [outgoing])
    }

    // MARK: Edit and Duplicate

    @Test func aStartingBalanceIsEditedOnItsOwnAndNeverDuplicated() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let wallet = try Wallet.create(
            name: "Credit line", startingBalance: Money(cents: -250_00), on: today, in: context
        )
        let startingBalance = try #require(wallet.transactions?.first)

        #expect(startingBalance.editFlow == .startingBalance)
        #expect(!startingBalance.canBeDuplicated)
    }

    @Test func anOrdinaryTransactionIsEditedAndDuplicatedInTheAddSheet() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let cafe = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Café" })
        let coffee = record("coffee", -4_50, in: checking)
        coffee.category = cafe

        #expect(coffee.editFlow == .addSheet)
        #expect(coffee.canBeDuplicated)
    }

    @Test(arguments: [LockedRole.debtCollection, .repayment])
    func whatRecordPaymentFiledIsNeitherEditedNorDuplicatedHere(role: LockedRole) throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let payment = record("payment", 60_00, in: checking)
        payment.category = try context.lockedCategory(role)

        #expect(payment.editFlow == nil)
        #expect(!payment.canBeDuplicated)
    }

    @Test func aLinkedTransactionIsNeitherEditedNorDuplicatedHere() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let link = UUID()
        let loan = record("Pasha", -100_00, in: checking, link: link, kind: .loanOrDebt)
        loan.category = try context.lockedCategory(.loan)
        let forgiven = record("forgave Pasha", -40_00, in: checking, link: link, kind: .loanOrDebt)
        forgiven.category = try context.lockedCategory(.otherExpense)

        #expect(forgiven.editFlow == nil)
        #expect(!forgiven.canBeDuplicated)
    }

    @Test(arguments: [LockedRole.loan, .debt])
    func aLoanOrDebtWithPaymentsIsStillEditedAndDuplicatedInTheAddSheet(role: LockedRole) throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let original = record("Pasha", -100_00, in: checking, link: UUID(), kind: .loanOrDebt)
        original.category = try context.lockedCategory(role)

        #expect(original.editFlow == .addSheet)
        #expect(original.canBeDuplicated)
    }
}
