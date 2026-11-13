import Foundation
import SwiftData
import Testing
@testable import Grosh

@MainActor
@Suite(.namedInTheLog)
struct WalletBalanceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func record(_ cents: Int, on day: CalendarDay, in wallet: Wallet) {
        context.record(cents, on: day, in: wallet)
    }

    @Test func balanceIsTheSumOfTransactionsDatedTodayOrEarlier() {
        let checking = context.addWallet("Checking")
        record(100_00, on: CalendarDay(year: 2026, month: 9, day: 1), in: checking)
        record(-12_76, on: CalendarDay(year: 2026, month: 10, day: 8), in: checking)
        record(-5_00, on: today, in: checking)

        #expect(walletBalance(checking, asOf: today) == Money(cents: 82_24))
    }

    @Test func transactionsDatedAfterTodayDoNotChangeTheBalance() {
        let checking = context.addWallet("Checking")
        record(50_00, on: today, in: checking)
        record(-20_00, on: CalendarDay(year: 2026, month: 10, day: 10), in: checking)
        record(1_000_00, on: CalendarDay(year: 2027, month: 1, day: 1), in: checking)

        #expect(walletBalance(checking, asOf: today) == Money(cents: 50_00))
    }

    @Test func aFutureTransactionCountsOnceItsDayArrives() {
        let checking = context.addWallet("Checking")
        let tomorrow = CalendarDay(year: 2026, month: 10, day: 10)
        record(50_00, on: today, in: checking)
        record(-20_00, on: tomorrow, in: checking)

        #expect(walletBalance(checking, asOf: tomorrow) == Money(cents: 30_00))
    }

    @Test func totalAddsUpWalletsIncludedInTheTotal() {
        let checking = context.addWallet("Checking")
        let cash = context.addWallet("Cash")
        record(100_00, on: today, in: checking)
        record(25_50, on: today, in: cash)

        #expect(walletTotal([checking, cash], asOf: today) == [Money(cents: 125_50)])
    }

    @Test func totalLeavesOutWalletsNotIncludedInTheTotal() {
        let checking = context.addWallet("Checking")
        let brokerage = context.addWallet("Brokerage", includeInTotal: false)
        record(100_00, on: today, in: checking)
        record(5_000_00, on: today, in: brokerage)

        #expect(walletTotal([checking, brokerage], asOf: today) == [Money(cents: 100_00)])
    }

    @Test func totalLeavesOutArchivedWallets() {
        let checking = context.addWallet("Checking")
        let oldBank = context.addWallet("Old bank")
        record(100_00, on: today, in: checking)
        record(300_00, on: today, in: oldBank)
        oldBank.isArchived = true

        #expect(walletTotal([checking, oldBank], asOf: today) == [Money(cents: 100_00)])
    }

    @Test func totalIgnoresTransactionsDatedAfterToday() {
        let checking = context.addWallet("Checking")
        let cash = context.addWallet("Cash")
        record(100_00, on: today, in: checking)
        record(-40_00, on: CalendarDay(year: 2026, month: 11, day: 1), in: cash)

        #expect(walletTotal([checking, cash], asOf: today) == [Money(cents: 100_00)])
    }

    @Test func totalOfNoWalletsIsZero() {
        #expect(walletTotal([], asOf: today) == [Money(cents: 0)])
    }

    /// Home and the Wallet selector add every balance up in one pass over the shared ledger entries.
    @Test func balancesAddedUpAtOnceFromTheLedgerGiveEachWalletsBalance() throws {
        let checking = context.addWallet("Checking")
        let cash = context.addWallet("Cash")
        let brokerage = context.addWallet("Brokerage", includeInTotal: false)
        let empty = context.addWallet("Empty")
        record(100_00, on: CalendarDay(year: 2026, month: 9, day: 1), in: checking)
        record(-12_76, on: today, in: checking)
        record(-20_00, on: CalendarDay(year: 2026, month: 10, day: 10), in: checking)
        record(25_50, on: today, in: cash)
        record(5_000_00, on: today, in: brokerage)
        context.record(-9_00, on: today, in: cash).changeCounted { $0.deletedAt = .now }
        try context.save()

        let balances = WalletBalances(NotDeletedTransactions.Store.of(context).entries, asOf: today)

        #expect(balances.balance(of: checking) == Money(cents: 87_24))
        #expect(balances.balance(of: cash) == Money(cents: 25_50))
        #expect(balances.balance(of: brokerage) == Money(cents: 5_000_00))
        #expect(balances.balance(of: empty) == Money(cents: 0))
        #expect(balances.total(of: [checking, cash, brokerage, empty]) == [Money(cents: 112_74)])
    }
}
