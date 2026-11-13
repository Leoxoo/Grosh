import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Grosh

/// The balances Home, the Wallets list and the Wallet selector show, read from the saved month totals rather than from
/// every transaction: a wallet's balance today is the sum of its saved months up to and including this one, less this
/// month's transactions dated after today (ADR-0013).
@MainActor
@Suite(.namedInTheLog)
struct SavedBalanceTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    private func record(_ cents: Int, on day: CalendarDay, in wallet: Wallet? = nil) {
        context.record(cents, on: day, in: wallet ?? checking)
    }

    @Test func aWalletsBalanceAddsUpItsSavedMonths() throws {
        let cash = context.addWallet("Cash")
        record(100_00, on: day(2025, 12, 1))
        record(-12_76, on: day(2026, 9, 8))
        record(-5_00, on: today)
        record(25_50, on: day(2026, 10, 2), in: cash)
        try context.save()

        let balances = try WalletBalances.read(asOf: today, in: context)

        #expect(balances.balance(of: checking) == Money(cents: 82_24))
        #expect(balances.balance(of: cash) == Money(cents: 25_50))
        #expect(balances.total(of: [checking, cash]) == [Money(cents: 107_74)])
    }

    @Test func transactionsDatedAfterTodayDontCountYetInThisMonthOrLater() throws {
        record(50_00, on: today)
        record(-20_00, on: day(2026, 10, 10))
        record(-7_00, on: day(2026, 10, 31))
        record(1_000_00, on: day(2026, 11, 1))
        try context.save()

        let balances = try WalletBalances.read(asOf: today, in: context)

        #expect(balances.balance(of: checking) == Money(cents: 50_00))
    }

    @Test func aTransactionDatedAfterTodayCountsOnceItsDayArrives() throws {
        record(50_00, on: today)
        record(-20_00, on: day(2026, 10, 10))
        try context.save()

        let balances = try WalletBalances.read(asOf: day(2026, 10, 10), in: context)

        #expect(balances.balance(of: checking) == Money(cents: 30_00))
    }

    @Test func aTransactionInRecentlyDeletedDatedAfterTodayIsTakenOffNothing() throws {
        record(50_00, on: today)
        context.record(-20_00, on: day(2026, 10, 20), in: checking).changeCounted { $0.deletedAt = .now }
        try context.save()

        let balances = try WalletBalances.read(asOf: today, in: context)

        #expect(balances.balance(of: checking) == Money(cents: 50_00))
    }

    @Test func aMonthStillDirtyWhenTheBalancesAreReadIsCountedWithoutSaving() throws {
        // Saved where nothing counts the totals after a save, as when the app stopped between a save and its count.
        let container = try TestStore.makeContainer(countingEachSave: false)
        let other = container.mainContext
        let cash = other.addWallet("Cash")
        other.record(40_00, on: day(2026, 9, 3), in: cash)
        try other.save()
        try WalletMonthTotals.countDirtyMonths(in: other)
        other.record(-12_00, on: day(2026, 10, 3), in: cash)
        other.record(-3_00, on: day(2026, 10, 25), in: cash)
        try other.save()
        let saves = SaveCount(other)

        let balances = try WalletBalances.read(asOf: today, in: other)

        #expect(balances.balance(of: cash) == Money(cents: 28_00))
        // A screen reads its balances while it draws, when nothing may save.
        #expect(saves.count == 0)
    }

    // MARK: On screen

    /// Home, the Wallets list and the Wallet selector read their balances through ``SavedWalletBalances``.
    @Test func aScreensBalancesAreReadAgainAfterEachSave() throws {
        let shown = ShownBalances()
        let screen = Hosted(
            BalanceProbe(wallet: checking, shown: shown).environment(\.today, today), container: store.container
        )
        #expect(shown.last == 0)

        record(-5_00, on: today)
        try context.save()
        screen.settle()
        #expect(shown.last == -5_00)

        record(-1_00, on: day(2026, 10, 20))
        try context.save()
        screen.settle()
        #expect(shown.last == -5_00)
    }
}

/// The balance a ``BalanceProbe`` last drew, in cents.
@MainActor
private final class ShownBalances {
    var last: Int?
}

/// A screen showing one wallet's balance as Home does.
private struct BalanceProbe: View {
    let wallet: Wallet
    let shown: ShownBalances
    @SavedWalletBalances private var balances

    var body: some View {
        let cents = balances.balance(of: wallet).cents
        shown.last = cents
        return Text(verbatim: "\(cents)")
    }
}
