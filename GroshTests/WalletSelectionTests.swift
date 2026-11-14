import SwiftData
import Testing
@testable import Grosh

/// The Transactions tab's wallet selector: the Total, or one wallet.
@MainActor
@Suite(.namedInTheLog)
struct WalletSelectionTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today

    init() throws {
        container = try TestStore.makeContainer()
    }

    @discardableResult
    private func record(_ note: String, _ cents: Int, in wallet: Wallet, on day: CalendarDay? = nil) -> Transaction {
        context.record(cents, on: day ?? today, in: wallet, note: note)
    }

    @Test func oneWalletShowsOnlyItsOwnTransactions() {
        let checking = context.addWallet("Checking")
        let cash = context.addWallet("Cash")
        let all = [record("rent", -900_00, in: checking), record("tip", 5_00, in: cash)]

        #expect(all.filter(WalletSelection.wallet(checking).includes).map(\.note) == ["rent"])
    }

    @Test func theTotalShowsTheTransactionsOfWalletsCountedInTheTotal() throws {
        let checking = context.addWallet("Checking")
        let brokerage = context.addWallet("Brokerage")
        brokerage.includeInTotal = false
        let oldBank = context.addWallet("Old bank")
        try oldBank.archive(today: today)
        let all = [
            record("rent", -900_00, in: checking),
            record("stock sold", 300_00, in: brokerage),
            record("closing fee", -5_00, in: oldBank),
        ]

        #expect(all.filter(WalletSelection.total.includes).map(\.note) == ["rent"])
    }

    @Test func theHeaderShowsTheSelectionsBalanceToday() {
        let checking = context.addWallet("Checking")
        let brokerage = context.addWallet("Brokerage")
        brokerage.includeInTotal = false
        record("salary", 100_00, in: checking)
        record("rent due", -900_00, in: checking, on: CalendarDay(year: 2026, month: 11, day: 1))
        record("stock sold", 300_00, in: brokerage)
        let wallets = [checking, brokerage]

        let balances = WalletBalances(of: wallets, asOf: today)
        #expect(balances.balance(of: WalletSelection.total, wallets: wallets) == [Money(cents: 100_00)])
        #expect(balances.balance(of: WalletSelection.wallet(brokerage), wallets: wallets) == [Money(cents: 300_00)])
    }
}
