import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The balances a wallet picker shows when it opts in, as the Transfer sheet's From and To do: the chosen wallet's
/// balance today on a Balance row of its own under the picker, and each wallet's balance today in its dropdown option.
@MainActor
struct WalletPickerBalanceTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let unitedStates = Locale(identifier: "en_US")

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func wallet(_ name: String) -> Wallet {
        let wallet = Wallet(name: name)
        context.insert(wallet)
        return wallet
    }

    private func record(_ cents: Int, on day: CalendarDay? = nil, in wallet: Wallet) {
        let transaction = Transaction(amount: Money(cents: cents), day: day ?? today, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet
    }

    @Test func theBalanceRowShowsTheChosenWalletsBalanceToday() {
        let checking = wallet("Checking")
        record(1_000_00, on: CalendarDay(year: 2026, month: 9, day: 1), in: checking)
        record(-12_76, in: checking)

        #expect(checking.balance(asOf: today).formatted(locale: unitedStates) == "$987.24")
    }

    @Test func eachDropdownOptionShowsItsWalletsBalanceToday() {
        let checking = wallet("Checking")
        let cash = wallet("Cash")
        let savings = wallet("Savings")
        record(1_000_00, on: CalendarDay(year: 2026, month: 9, day: 1), in: checking)
        record(-12_76, in: checking)
        record(-5_00, in: cash)

        let options = [checking, cash, savings].map { $0.balance(asOf: today).formatted(locale: unitedStates) }

        #expect(options == ["$987.24", "-$5.00", "$0.00"])
    }

    @Test func theBalancesAreInTheWalletsOwnCurrency() {
        let euros = wallet("Euro account")
        euros.currencyCode = "EUR"
        record(50_00, in: euros)

        #expect(euros.balance(asOf: today).formatted(locale: unitedStates) == "€50.00")
    }

    @Test func aTransferDatedAfterTodayDoesNotChangeTheBalancesShown() throws {
        try CategorySeeder.seedIfNeeded(in: context)
        let checking = wallet("Checking")
        let savings = wallet("Savings")
        record(1_000_00, in: checking)
        var nextWeek = TransferDraft(day: today.adding(days: 7))
        nextWeek.from = checking
        nextWeek.to = savings
        nextWeek.amount = Money(cents: 250_00)

        try Transfer.create(nextWeek, in: context)

        #expect(checking.balance(asOf: today).formatted(locale: unitedStates) == "$1,000.00")
        #expect(savings.balance(asOf: today).formatted(locale: unitedStates) == "$0.00")
    }
}
