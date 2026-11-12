import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Recently Deleted: deleted transactions and wallets wait there for 30 days, counting in no balance, list or Total,
/// until they are restored or removed for good.
@MainActor
@Suite(.namedInTheLog)
struct RecentlyDeletedTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today
    private let deletedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let checking: Wallet
    private let savings: Wallet
    private let links = TestLinks()

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = container.mainContext.addWallet("Checking")
        savings = container.mainContext.addWallet("Savings")
    }

    @discardableResult
    private func record(_ note: String, _ cents: Int, in wallet: Wallet, link: UUID? = nil) -> Transaction {
        let transaction = context.record(cents, on: today, in: wallet, note: note)
        links.put(transaction, on: link, as: .transfer)
        return transaction
    }

    private func bin() throws -> RecentlyDeleted {
        try RecentlyDeleted(in: context)
    }

    private func days(_ count: Double) -> TimeInterval {
        count * 24 * 60 * 60
    }

    // MARK: Deleting a transaction

    @Test func deletingATransactionMovesItToRecentlyDeletedAndOutOfItsWalletsBalance() throws {
        record("salary", 100_00, in: checking)
        let coffee = record("coffee", -4_50, in: checking)

        try coffee.delete(.onlySelected, in: context, at: deletedAt)

        #expect(coffee.isInRecentlyDeleted)
        #expect(try bin().transactions == [coffee])
        #expect(walletBalance(checking, asOf: today) == Money(cents: 100_00))
        #expect(try context.fetch(Transaction.notDeleted).map(\.note) == ["salary"])
        #expect(try context.transactionCount() == 2)
    }

    @Test func deletingWithRelatedMovesEachLinkedTransactionToTheBinOnItsOwn() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        let incoming = record("from checking", 500_00, in: savings, link: transfer)

        try outgoing.delete(.withRelated, in: context, at: deletedAt)

        #expect(try Set(bin().transactions) == [outgoing, incoming])
        #expect(walletBalance(savings, asOf: today) == Money(cents: 0))
    }

    @Test func restoringATransactionBringsItBackLinkedAsBefore() throws {
        let transfer = UUID()
        let outgoing = record("to savings", -500_00, in: checking, link: transfer)
        let incoming = record("from checking", 500_00, in: savings, link: transfer)
        try outgoing.delete(.onlySelected, in: context, at: deletedAt)
        #expect(try incoming.related(in: context).isEmpty)

        try outgoing.restore()

        #expect(!outgoing.isInRecentlyDeleted)
        #expect(try incoming.related(in: context) == [outgoing])
        #expect(walletBalance(checking, asOf: today) == Money(cents: -500_00))
        #expect(try bin().isEmpty)
    }

    @Test func aDeletedLoanLeavesDebtsAndLoansAndRecentTransactions() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let lent = record("lent to Pasha", -100_00, in: checking)
        lent.category = try context.lockedCategory(.loan)
        lent.setPeople([try Person.add(named: "Pasha", in: context)])
        #expect(try context.fetch(DebtsAndLoans.records) == [lent])

        try lent.delete(.onlySelected, in: context, at: deletedAt)

        #expect(try context.fetch(Transaction.recent(limit: 5, asOf: today)).isEmpty)
        #expect(try context.fetch(DebtsAndLoans.records).isEmpty)
    }

    @Test func aLoansPaymentInTheBinStillKeepsItsWalletAndCategory() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let loan = try context.recordLoanOrDebt(.loan, 100_00, with: context.person("Pasha"), on: today, in: checking)
        let collection = try context.pay(60_00, on: loan, on: today).payment
        try collection.delete(.onlySelected, in: context, at: deletedAt)

        var editing = TransactionDraft(editing: loan)
        #expect(editing.isLockedByPayments)
        editing.wallet = savings
        #expect(throws: DebtLoanRuleError.lockedByPayments) { try loan.update(with: editing) }

        var smaller = TransactionDraft(editing: loan)
        smaller.amount = Money(cents: 10_00)
        #expect(throws: DebtLoanRuleError.amountBelowPaid) { try loan.update(with: smaller) }
        #expect(loan.amountCents == -100_00)
    }

    @Test func aPaymentCantBeRestoredOntoALoanForgivenSinceItWasDeleted() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let loan = try context.recordLoanOrDebt(.loan, 100_00, with: context.person("Pasha"), on: today, in: checking)
        let collection = try context.pay(60_00, on: loan, on: today).payment
        try collection.delete(.onlySelected, in: context, at: deletedAt)
        try context.forgive(loan, on: today)

        #expect(collection.restoreBlocker == .loanOrDebtIsForgiven)
        #expect(throws: RecentlyDeletedError.loanOrDebtIsForgiven) { try collection.restore() }

        try loan.unforgive()
        try collection.restore()
        #expect(try #require(try LoanOrDebt(loan, in: context)).outstanding == Money(cents: 40_00))
    }

    // MARK: Deleting a wallet

    @Test func deletingAWalletMovesItAndAllItsTransactionsToTheBinAsOneItem() throws {
        checking.includeInTotal = true
        savings.includeInTotal = true
        record("salary", 100_00, in: checking)
        record("coffee", -4_50, in: checking)
        let transfer = UUID()
        record("to savings", -20_00, in: checking, link: transfer)
        let incoming = record("from checking", 20_00, in: savings, link: transfer)

        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        let bin = try bin()
        #expect(bin.wallets == [checking])
        #expect(bin.transactions.isEmpty)
        #expect(checking.transactionsDeletedWithIt.count == 3)
        #expect(try context.fetch(Wallet.unarchived) == [savings])
        #expect(walletTotal([checking, savings], asOf: today) == [Money(cents: 20_00)])
        // The transfer's other half stays in its wallet, its own half now a dash.
        #expect(!incoming.isInRecentlyDeleted)
        #expect(try incoming.related(in: context).isEmpty)
    }

    @Test func transactionsDeletedWithAWalletAreRestoredOnlyWithIt() throws {
        let salary = record("salary", 100_00, in: checking)
        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        #expect(throws: RecentlyDeletedError.deletedWithWallet) { try salary.restore() }
        #expect(throws: RecentlyDeletedError.deletedWithWallet) { try salary.deleteForever() }

        try checking.restore(today: today)

        #expect(!checking.isInRecentlyDeleted)
        #expect(!salary.isInRecentlyDeleted)
        #expect(walletBalance(checking, asOf: today) == Money(cents: 100_00))
        #expect(try bin().isEmpty)
    }

    @Test func aTransactionDeletedBeforeItsWalletStaysInTheBinWhenTheWalletIsRestored() throws {
        record("salary", 100_00, in: checking)
        let coffee = record("coffee", -4_50, in: checking)
        try coffee.delete(.onlySelected, in: context, at: deletedAt)
        let nextDay = deletedAt.addingTimeInterval(days(1))
        try checking.delete(today: CalendarDay(nextDay), at: nextDay)

        #expect(try bin().transactions == [coffee])
        #expect(coffee.restoreBlocker == .walletIsDeleted)
        #expect(throws: RecentlyDeletedError.walletIsDeleted) { try coffee.restore() }

        try checking.restore(today: today)

        #expect(coffee.isInRecentlyDeleted)
        #expect(walletBalance(checking, asOf: today) == Money(cents: 100_00))
        try coffee.restore()
        #expect(walletBalance(checking, asOf: today) == Money(cents: 95_50))
    }

    @Test func aDeletedWalletsCardsWaitWithItAndGoWithItForGood() throws {
        let chase = try Card.create(CardDraft(name: "Chase", kind: .credit, payingWallet: checking), in: context)
        let coffee = record("coffee", -4_50, in: checking)
        coffee.card = chase

        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)
        #expect(try !context.fetch(Card.unarchived).contains(chase))
        #expect(try !context.fetch(Card.listed).contains(chase))

        try checking.restore(today: today)
        #expect(try context.fetch(Card.unarchived).contains(chase))
        #expect(try context.fetch(Card.listed).contains(chase))

        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)
        try checking.deleteForever()
        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
    }

    // MARK: 30 days

    @Test func eachItemShowsTheDaysItHasLeft() {
        #expect(RecentlyDeleted.daysLeft(since: deletedAt, now: deletedAt) == 30)
        #expect(RecentlyDeleted.daysLeft(since: deletedAt, now: deletedAt.addingTimeInterval(days(1))) == 29)
        #expect(RecentlyDeleted.daysLeft(since: deletedAt, now: deletedAt.addingTimeInterval(days(29.5))) == 1)
        #expect(RecentlyDeleted.daysLeft(since: deletedAt, now: deletedAt.addingTimeInterval(days(31))) == 0)
    }

    @Test func itemsOlderThan30DaysAreRemovedForGoodWhenPurged() throws {
        record("salary", 100_00, in: checking)
        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)
        let coffee = record("coffee", -4_50, in: savings)
        try coffee.delete(.onlySelected, in: context, at: deletedAt.addingTimeInterval(days(10)))
        record("lunch", -12_00, in: savings)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(days(29)))
        #expect(try context.transactionCount() == 3)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(days(30)))
        #expect(try context.fetch(FetchDescriptor<Wallet>()) == [savings])
        #expect(try bin().transactions == [coffee])
        #expect(try context.transactionCount() == 2)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(days(40)))
        #expect(try bin().isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).map(\.note) == ["lunch"])
    }

    // MARK: Delete Forever and Empty Bin

    @Test func deletingForeverRemovesOneItemForGood() throws {
        let coffee = record("coffee", -4_50, in: savings)
        record("salary", 100_00, in: checking)
        try coffee.delete(.onlySelected, in: context, at: deletedAt)
        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        try coffee.deleteForever()
        #expect(try context.transactionCount() == 1)

        try checking.deleteForever()
        #expect(try context.transactionCount() == 0)
        #expect(try context.fetch(FetchDescriptor<Wallet>()) == [savings])
    }

    @Test func emptyingTheBinRemovesEverythingInItAndNothingElse() throws {
        record("salary", 100_00, in: checking)
        let coffee = record("coffee", -4_50, in: savings)
        record("lunch", -12_00, in: savings)
        try coffee.delete(.onlySelected, in: context, at: deletedAt)
        try checking.delete(today: CalendarDay(deletedAt), at: deletedAt)

        try RecentlyDeleted.empty(in: context)

        #expect(try bin().isEmpty)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).map(\.note) == ["lunch"])
        #expect(try context.fetch(FetchDescriptor<Wallet>()) == [savings])
    }

    @Test func onlySomethingInTheBinCanBeRestoredOrDeletedForever() throws {
        let coffee = record("coffee", -4_50, in: checking)

        #expect(throws: RecentlyDeletedError.notDeleted) { try coffee.restore() }
        #expect(throws: RecentlyDeletedError.notDeleted) { try coffee.deleteForever() }
        #expect(throws: RecentlyDeletedError.notDeleted) { try checking.restore(today: today) }
    }
}
