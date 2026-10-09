import SwiftData
import Testing
@testable import Grosh

/// The Transactions tab's wallet selector: the Total, or one wallet.
@MainActor
struct WalletSelectionTests {
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

    @discardableResult
    private func record(_ note: String, _ cents: Int, in wallet: Wallet, on day: CalendarDay? = nil) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day ?? today, wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = wallet
        return transaction
    }

    @Test func oneWalletShowsOnlyItsOwnTransactions() {
        let checking = wallet("Checking")
        let cash = wallet("Cash")
        let all = [record("rent", -900_00, in: checking), record("tip", 5_00, in: cash)]

        #expect(all.filter(WalletSelection.wallet(checking).includes).map(\.note) == ["rent"])
    }

    @Test func theTotalShowsTheTransactionsOfWalletsCountedInTheTotal() throws {
        let checking = wallet("Checking")
        let brokerage = wallet("Brokerage")
        brokerage.includeInTotal = false
        let oldBank = wallet("Old bank")
        try oldBank.archive()
        let all = [
            record("rent", -900_00, in: checking),
            record("stock sold", 300_00, in: brokerage),
            record("closing fee", -5_00, in: oldBank),
        ]

        #expect(all.filter(WalletSelection.total.includes).map(\.note) == ["rent"])
    }

    @Test func theHeaderShowsTheSelectionsBalanceToday() {
        let checking = wallet("Checking")
        let brokerage = wallet("Brokerage")
        brokerage.includeInTotal = false
        record("salary", 100_00, in: checking)
        record("rent due", -900_00, in: checking, on: CalendarDay(year: 2026, month: 11, day: 1))
        record("stock sold", 300_00, in: brokerage)
        let wallets = [checking, brokerage]

        #expect(WalletSelection.total.balance(asOf: today, wallets: wallets) == Money(cents: 100_00))
        #expect(WalletSelection.wallet(brokerage).balance(asOf: today, wallets: wallets) == Money(cents: 300_00))
    }
}
