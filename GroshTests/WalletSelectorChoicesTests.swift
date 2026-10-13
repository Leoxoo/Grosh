import SwiftData
import Testing
@testable import Grosh

/// What the Wallet selector lists when opened: the Total, the wallets included in it and those left out, each with its
/// balance today.
@MainActor
struct WalletSelectorChoicesTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
    }

    private func wallet(_ name: String, includeInTotal: Bool = true) -> Wallet {
        let wallet = Wallet(name: name)
        wallet.includeInTotal = includeInTotal
        context.insert(wallet)
        return wallet
    }

    private func record(_ cents: Int, in wallet: Wallet, on day: CalendarDay? = nil) {
        let transaction = Transaction(amount: Money(cents: cents), day: day ?? today, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet
    }

    @Test func walletsCountedInTheTotalAreListedApartFromThoseLeftOut() {
        let checking = wallet("Checking")
        let brokerage = wallet("Brokerage", includeInTotal: false)
        let cash = wallet("Cash")
        let pension = wallet("Pension", includeInTotal: false)

        let choices = WalletSelectorChoices(wallets: [checking, brokerage, cash, pension], asOf: today)

        #expect(choices.includedInTotal.map(\.selection) == [.wallet(checking), .wallet(cash)])
        #expect(choices.notInTotal.map(\.selection) == [.wallet(brokerage), .wallet(pension)])
    }

    @Test func archivedAndDeletedWalletsAreNotListed() throws {
        let checking = wallet("Checking")
        let oldBank = wallet("Old bank")
        try oldBank.archive(today: today)
        let closed = wallet("Closed")
        try closed.delete()

        let choices = WalletSelectorChoices(wallets: [checking, oldBank, closed], asOf: today)

        #expect(choices.includedInTotal.map(\.selection) == [.wallet(checking)])
        // Every wallet still listed counts in the Total, so there is no "Not in total" section.
        #expect(choices.notInTotal.isEmpty)
    }

    @Test func eachRowShowsItsBalanceTodayInItsOwnCurrency() {
        let checking = wallet("Checking")
        let cash = wallet("Cash")
        let brokerage = wallet("Brokerage", includeInTotal: false)
        let euros = wallet("Euros", includeInTotal: false)
        euros.currencyCode = "EUR"
        record(100_00, in: checking)
        record(-900_00, in: checking, on: CalendarDay(year: 2026, month: 11, day: 1))
        record(25_00, in: cash)
        record(300_00, in: brokerage)
        record(40_00, in: euros)

        let choices = WalletSelectorChoices(wallets: [checking, cash, brokerage, euros], asOf: today)

        // The Total card: checking and cash, not the rent due next month nor the wallets left out.
        #expect(choices.total.selection == .total)
        #expect(choices.total.balance == Money(cents: 125_00))
        #expect(choices.includedInTotal.map(\.balance) == [Money(cents: 100_00), Money(cents: 25_00)])
        #expect(choices.notInTotal.map(\.balance) == [Money(cents: 300_00), Money(cents: 40_00, currencyCode: "EUR")])
    }
}
