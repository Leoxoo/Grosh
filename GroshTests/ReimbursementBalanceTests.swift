import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Where an Expense's Reimbursements count: balances, Opening and Ending balances, day totals and the transaction list
/// use the net, while a Card's statement and the Card filter's total still use what the Card was charged.
@MainActor
@Suite(.namedInTheLog)
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
        let dinner = try store.recordDinner()
        try context.payBack(20_00, on: today, to: dinner)
        return dinner
    }

    // MARK: Balances

    @Test func aWalletsBalanceCountsTheNet() throws {
        try reimbursedDinner()

        #expect(walletBalance(checking, asOf: today) == Money(cents: 960_00))
    }

    @Test func theTotalAndTheWalletSelectorCountTheNet() throws {
        try reimbursedDinner()

        #expect(walletTotal([checking], asOf: today) == [Money(cents: 960_00)])
        let balances = WalletBalances(of: [checking], asOf: today)
        #expect(balances.balance(of: WalletSelection.total, wallets: [checking]) == [Money(cents: 960_00)])
        #expect(balances.balance(of: WalletSelection.wallet(checking), wallets: [checking]) == [Money(cents: 960_00)])
    }

    @Test func aTransactionDatedAfterTodayCountsItsNetOnceItsDayArrives() throws {
        let tomorrow = day(2026, 10, 13)
        let dinner = try store.record(-60_00, "Restaurants", on: tomorrow)
        try context.payBack(20_00, on: today, to: dinner)

        #expect(walletBalance(checking, asOf: today) == Money(cents: 0))
        #expect(walletBalance(checking, asOf: tomorrow) == Money(cents: -40_00))
    }

    @Test func aBalanceAdjustmentSeesTheNetInTheRecordedBalance() throws {
        let dinner = try store.recordDinner()
        try context.payBack(20_00, on: today, to: dinner)
        let adjustment = try store.record(5_00, "Collect Interest", .income, on: today)
        adjustment.isBalanceAdjustment = true

        #expect(try balanceChange(of: adjustment)?.recorded == Money(cents: -40_00))
        #expect(try balanceChange(of: adjustment)?.actual == Money(cents: -35_00))
    }

    // MARK: Opening and Ending balance, the list

    @Test func openingAndEndingBalancesCountTheNet() throws {
        try reimbursedDinner()
        let october = Period.month(CalendarMonth(today))
        let transactions = try context.fetch(Transaction.notDeleted)

        for summary in [
            PeriodSummary(of: transactions, in: october, today: today),
            PeriodSummary(of: transactions.map(LedgerEntry.init), in: october, today: today),
        ] {
            #expect(summary.openingBalance == Money(cents: 1_000_00))
            #expect(summary.endingBalance == Money(cents: 960_00))
            #expect(summary.difference == Money(cents: -40_00))
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

        let october = Period.month(CalendarMonth(today)).days(today: today)

        #expect(TransactionListing([dinner], showing: .total, on: october).total == Money(cents: -40_00))
        #expect(TransactionListing([dinner], showing: .wallet(checking), on: october).total == Money(cents: -40_00))
    }

    @Test func aRowsLedgerEntryIsReadAgainWhenItsReimbursementsChange() throws {
        let dinner = try store.recordDinner()
        try context.save()
        let shared = NotDeletedTransactions.Store.of(context)
        func entry() throws -> LedgerEntry {
            try #require(shared.entries.first { $0.transaction === dinner })
        }
        #expect(try entry().netCents == -60_00)

        let reimbursement = try context.payBack(20_00, on: today, to: dinner)
        #expect(try entry().netCents == -40_00)

        var draft = ReimbursementDraft(editing: reimbursement)
        draft.entry = AmountEntry(cents: 35_00)
        try reimbursement.update(with: draft)
        #expect(try entry().netCents == -25_00)

        try reimbursement.delete()
        #expect(try entry().netCents == -60_00)
    }

    /// Performance contract (the 16k store, `docs/agents/architecture.md`), not a behaviour: loading every transaction
    /// for the balances reads each one's net without reading its Reimbursements, which would fault them in one
    /// transaction at a time, so what they add up to is stored on the transaction itself. The behaviour is
    /// `aRowsLedgerEntryIsReadAgainWhenItsReimbursementsChange`.
    @Test func whatTheReimbursementsAddUpToIsStoredOnTheTransaction() throws {
        let dinner = try reimbursedDinner()
        let entry = try context.payBack(15_00, on: today, to: dinner)
        let reimbursedBy35 = FetchDescriptor<Transaction>(predicate: #Predicate { $0.reimbursedCents == 35_00 })

        #expect(try context.fetch(reimbursedBy35) == [dinner])

        try entry.delete()
        #expect(try context.fetch(reimbursedBy35).isEmpty)
        #expect(dinner.reimbursedCents == 20_00)
    }

    // MARK: Cards

    @Test func aCardStatementTotalIgnoresReimbursementsWhileTheWalletBalanceDoesNot() throws {
        let chase = try context.addCard("Chase", paidFrom: checking)
        let dinner = try store.recordDinner()
        dinner.card = chase
        try context.payBack(20_00, on: today, to: dinner)
        let shown = try chase.statement(for: chase.period(containing: today), today: today).transactions

        #expect(shown == [dinner])
        #expect(shown.charged == Money(cents: -60_00))
        #expect(shown.net == Money(cents: -40_00))
        #expect(walletBalance(checking, asOf: today) == Money(cents: -40_00))
    }

    @Test func aCardStatementsDayTotalsKeepWhatTheCardWasChargedWhileOtherListsCountTheNet() throws {
        let chase = try context.addCard("Chase", paidFrom: checking)
        let dinner = try store.recordDinner()
        let coffee = try store.record(-4_00, "Café", on: day(2026, 10, 3))
        dinner.card = chase
        coffee.card = chase
        try context.payBack(20_00, on: today, to: dinner)

        let statement = try chase.statement(for: chase.period(containing: today), today: today)
        let days = TransactionDay.days(of: statement.transactions)

        #expect(days.map { $0.total(.charged) } == [Money(cents: -64_00)])
        #expect(days.map { $0.total(.net) } == [Money(cents: -44_00)])
        #expect(days.map(\.net) == days.map { $0.total(.net) })
    }

    @Test func aStatementPeriodsLeadInTransactionsKeepTheirOriginalAmount() throws {
        let chase = try context.addCard("Chase", paidFrom: checking, statementDay: 15)
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 9, 15))
        dinner.card = chase
        try context.payBack(20_00, on: today, to: dinner)
        let current = chase.period(containing: today)
        let leadIns = try chase.statement(for: current, today: today).leadIns

        #expect(leadIns == [dinner])
        #expect((try chase.statement(for: current, today: today).transactions + leadIns).charged == Money(cents: -60_00))
    }

    @Test func theCardFiltersTotalIgnoresReimbursements() throws {
        let chase = try context.addCard("Chase", paidFrom: checking)
        let dinner = try store.recordDinner()
        dinner.card = chase
        let lunch = try store.record(-30_00, "Restaurants", on: day(2026, 10, 4))
        try context.payBack(20_00, on: today, to: dinner)

        let october = Period.month(CalendarMonth(today)).days(today: today)
        func listing(_ filter: TransactionFilter) -> TransactionListing {
            TransactionListing([dinner, lunch], showing: .total, on: october, filter: filter)
        }

        #expect(listing(TransactionFilter(card: chase)).transactions == [dinner])
        #expect(listing(TransactionFilter(card: chase)).listed == .charged)
        #expect(listing(TransactionFilter(card: chase)).total == Money(cents: -60_00))
        #expect(listing(TransactionFilter()).total == Money(cents: -70_00))
        #expect(listing(TransactionFilter(wallet: checking)).total == Money(cents: -70_00))
    }
}
