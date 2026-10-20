import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Where an Expense's Reimbursements count: balances, Opening and Ending balances, day totals and the transaction list
/// use the net, while a Card's statement and the Card filter's total still use what the Card was charged.
@MainActor
struct ReimbursementBalanceTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A $60 dinner on the 3rd after a $1,000 salary in September, with $20 of it paid back: $980 less $40 in Checking.
    @discardableResult
    private func reimbursedDinner() throws -> Transaction {
        try store.record(1_000_00, "Salary", .income, on: day(2026, 9, 1))
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        try payBack(20_00, to: dinner)
        return dinner
    }

    @discardableResult
    private func payBack(_ cents: Int, to expense: Transaction) throws -> Reimbursement {
        try Reimbursement.add(ReimbursementDraft(amount: Money(cents: cents), day: today), to: expense, in: context)
    }

    private func addCard(statementDay: Int? = nil) throws -> Card {
        try Card.create(CardDraft(name: "Chase", kind: .credit, payingWallet: checking, statementDay: statementDay), in: context)
    }

    // MARK: Balances

    @Test func aWalletsBalanceCountsTheNet() throws {
        try reimbursedDinner()

        #expect(checking.balance(asOf: today) == Money(cents: 960_00))
    }

    @Test func theTotalAndTheWalletSelectorCountTheNet() throws {
        try reimbursedDinner()

        #expect(Wallet.total(of: [checking], asOf: today) == Money(cents: 960_00))
        #expect(WalletSelection.total.balance(asOf: today, wallets: [checking]) == Money(cents: 960_00))
        #expect(WalletSelection.wallet(checking).balance(asOf: today, wallets: [checking]) == Money(cents: 960_00))
    }

    @Test func theBalancesAddedUpFromLedgerEntriesCountTheNet() throws {
        try reimbursedDinner()
        let entries = try context.fetch(Transaction.notDeleted).map(LedgerEntry.init)

        let balances = WalletBalances(entries, asOf: today)

        #expect(balances.balance(of: checking) == Money(cents: 960_00))
        #expect(balances.total(of: [checking]) == Money(cents: 960_00))
    }

    @Test func aTransactionDatedAfterTodayCountsItsNetOnceItsDayArrives() throws {
        let tomorrow = day(2026, 10, 13)
        let dinner = try store.record(-60_00, "Restaurants", on: tomorrow)
        try payBack(20_00, to: dinner)

        #expect(checking.balance(asOf: today) == Money(cents: 0))
        #expect(checking.balance(asOf: tomorrow) == Money(cents: -40_00))
    }

    @Test func aBalanceAdjustmentSeesTheNetInTheRecordedBalance() throws {
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        try payBack(20_00, to: dinner)
        let adjustment = try store.record(5_00, "Collect Interest", .income, on: today)
        adjustment.isBalanceAdjustment = true

        #expect(adjustment.balanceChange?.recorded == Money(cents: -40_00))
        #expect(adjustment.balanceChange?.actual == Money(cents: -35_00))
    }

    // MARK: Opening and Ending balance, the list

    @Test func openingAndEndingBalancesCountTheNet() throws {
        let dinner = try reimbursedDinner()
        let october = Period.month(CalendarMonth(today))
        let transactions = try context.fetch(Transaction.notDeleted)

        for summary in [
            PeriodSummary(of: transactions, in: october, today: today),
            PeriodSummary(of: transactions.map(LedgerEntry.init), in: october, today: today),
        ] {
            #expect(summary.openingBalance == Money(cents: 1_000_00))
            #expect(summary.endingBalance == Money(cents: 960_00))
            #expect(summary.difference == dinner.net)
        }
    }

    @Test func aDaysTotalAndACategorysTotalCountTheNet() throws {
        let dinner = try reimbursedDinner()
        let coffee = try store.record(-4_00, "Café", on: day(2026, 10, 3))

        let days = TransactionDay.days(of: [dinner, coffee])
        let groups = TransactionCategoryGroup.groups(of: [dinner, coffee])

        #expect(days.map(\.net) == [Money(cents: -44_00)])
        #expect(groups.map(\.total) == [Money(cents: -40_00), Money(cents: -4_00)])
    }

    @Test func aSearchOrFilterTotalCountsTheNet() throws {
        let dinner = try reimbursedDinner()

        #expect(TransactionFilter().total(of: [dinner]) == Money(cents: -40_00))
        #expect([dinner].net == Money(cents: -40_00))
    }

    @Test func aRowsLedgerEntryIsReadAgainWhenItsReimbursementsChange() throws {
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        try context.save()
        let shared = NotDeletedTransactions.Store.of(context)
        func entry() throws -> LedgerEntry {
            try #require(shared.entries.first { $0.transaction === dinner })
        }
        #expect(try entry().netCents == -60_00)

        let reimbursement = try payBack(20_00, to: dinner)
        #expect(try entry().netCents == -40_00)

        var draft = ReimbursementDraft(editing: reimbursement)
        draft.amount = Money(cents: 35_00)
        try reimbursement.update(with: draft)
        #expect(try entry().netCents == -25_00)

        try reimbursement.delete()
        #expect(try entry().netCents == -60_00)
    }

    /// Loading every transaction for the balances reads each one's net without reading its Reimbursements, which would
    /// fault them in one transaction at a time: what they add up to is stored on the transaction itself.
    @Test func whatTheReimbursementsAddUpToIsStoredOnTheTransaction() throws {
        let dinner = try reimbursedDinner()
        let entry = try payBack(15_00, to: dinner)
        let reimbursedBy35 = FetchDescriptor<Transaction>(predicate: #Predicate { $0.reimbursedCents == 35_00 })

        #expect(try context.fetch(reimbursedBy35) == [dinner])

        try entry.delete()
        #expect(try context.fetch(reimbursedBy35).isEmpty)
        #expect(dinner.reimbursedCents == 20_00)
    }

    // MARK: Cards

    @Test func aCardStatementTotalIgnoresReimbursementsWhileTheWalletBalanceDoesNot() throws {
        let chase = try addCard()
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        dinner.card = chase
        try payBack(20_00, to: dinner)
        let shown = chase.transactions(in: chase.period(containing: today))

        #expect(shown == [dinner])
        #expect(shown.charged == Money(cents: -60_00))
        #expect(shown.net == Money(cents: -40_00))
        #expect(checking.balance(asOf: today) == Money(cents: -40_00))
    }

    @Test func aCardStatementsDayTotalsKeepWhatTheCardWasChargedWhileOtherListsCountTheNet() throws {
        let chase = try addCard()
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        let coffee = try store.record(-4_00, "Café", on: day(2026, 10, 3))
        dinner.card = chase
        coffee.card = chase
        try payBack(20_00, to: dinner)

        let days = TransactionDay.days(of: chase.transactions(in: chase.period(containing: today)))

        #expect(days.map { $0.total(.charged) } == [Money(cents: -64_00)])
        #expect(days.map { $0.total(.net) } == [Money(cents: -44_00)])
        #expect(days.map(\.net) == days.map { $0.total(.net) })
    }

    @Test func aStatementPeriodsLeadInTransactionsKeepTheirOriginalAmount() throws {
        let chase = try addCard(statementDay: 15)
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 9, 15))
        dinner.card = chase
        try payBack(20_00, to: dinner)
        let current = chase.period(containing: today)
        let leadIns = chase.leadInTransactions(in: current)

        #expect(leadIns == [dinner])
        #expect((chase.transactions(in: current) + leadIns).charged == Money(cents: -60_00))
    }

    @Test func theCardFiltersTotalIgnoresReimbursements() throws {
        let chase = try addCard()
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        dinner.card = chase
        let lunch = try store.record(-30_00, "Restaurants", on: day(2026, 10, 4))
        try payBack(20_00, to: dinner)

        #expect(TransactionFilter(card: chase).total(of: [dinner]) == Money(cents: -60_00))
        #expect(TransactionFilter().total(of: [dinner, lunch]) == Money(cents: -70_00))
        #expect(TransactionFilter(wallet: checking).total(of: [dinner, lunch]) == Money(cents: -70_00))
    }
}
