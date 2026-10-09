import SwiftData
import Testing
@testable import Grosh

@MainActor
struct WalletBalanceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func wallet(_ name: String) -> Wallet {
        let wallet = Wallet(name: name)
        context.insert(wallet)
        return wallet
    }

    private func record(_ cents: Int, on day: CalendarDay, in wallet: Wallet) {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet
    }

    @Test func balanceIsTheSumOfTransactionsDatedTodayOrEarlier() {
        let checking = wallet("Checking")
        record(100_00, on: CalendarDay(year: 2026, month: 9, day: 1), in: checking)
        record(-12_76, on: CalendarDay(year: 2026, month: 10, day: 8), in: checking)
        record(-5_00, on: today, in: checking)

        #expect(checking.balance(asOf: today) == Money(cents: 82_24))
    }

    @Test func transactionsDatedAfterTodayDoNotChangeTheBalance() {
        let checking = wallet("Checking")
        record(50_00, on: today, in: checking)
        record(-20_00, on: CalendarDay(year: 2026, month: 10, day: 10), in: checking)
        record(1_000_00, on: CalendarDay(year: 2027, month: 1, day: 1), in: checking)

        #expect(checking.balance(asOf: today) == Money(cents: 50_00))
    }

    @Test func aFutureTransactionCountsOnceItsDayArrives() {
        let checking = wallet("Checking")
        let tomorrow = CalendarDay(year: 2026, month: 10, day: 10)
        record(50_00, on: today, in: checking)
        record(-20_00, on: tomorrow, in: checking)

        #expect(checking.balance(asOf: tomorrow) == Money(cents: 30_00))
    }

    @Test func totalAddsUpWalletsIncludedInTheTotal() {
        let checking = wallet("Checking")
        let cash = wallet("Cash")
        record(100_00, on: today, in: checking)
        record(25_50, on: today, in: cash)

        #expect(Wallet.total(of: [checking, cash], asOf: today) == Money(cents: 125_50))
    }

    @Test func totalLeavesOutWalletsNotIncludedInTheTotal() {
        let checking = wallet("Checking")
        let brokerage = wallet("Brokerage")
        brokerage.includeInTotal = false
        record(100_00, on: today, in: checking)
        record(5_000_00, on: today, in: brokerage)

        #expect(Wallet.total(of: [checking, brokerage], asOf: today) == Money(cents: 100_00))
    }

    @Test func totalLeavesOutArchivedWallets() {
        let checking = wallet("Checking")
        let oldBank = wallet("Old bank")
        record(100_00, on: today, in: checking)
        record(300_00, on: today, in: oldBank)
        oldBank.isArchived = true

        #expect(Wallet.total(of: [checking, oldBank], asOf: today) == Money(cents: 100_00))
    }

    @Test func totalIgnoresTransactionsDatedAfterToday() {
        let checking = wallet("Checking")
        let cash = wallet("Cash")
        record(100_00, on: today, in: checking)
        record(-40_00, on: CalendarDay(year: 2026, month: 11, day: 1), in: cash)

        #expect(Wallet.total(of: [checking, cash], asOf: today) == Money(cents: 100_00))
    }

    @Test func totalOfNoWalletsIsZero() {
        #expect(Wallet.total(of: [], asOf: today) == Money(cents: 0))
    }
}
