import Foundation
import SwiftData
import Testing
@testable import Grosh

/// What the Wallet selector lists when opened: the Total, the wallets included in it and those left out, each with its
/// balance today.
@MainActor
@Suite(.namedInTheLog)
struct WalletSelectorChoicesTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = TestStore.today

    init() throws {
        container = try TestStore.makeContainer()
    }

    private func record(_ cents: Int, in wallet: Wallet, on day: CalendarDay? = nil) {
        context.record(cents, on: day ?? today, in: wallet)
    }

    /// The selector's rows for `wallets`, with their balances today.
    private func choices(_ wallets: [Wallet]) -> WalletSelectorChoices {
        WalletSelectorChoices(wallets: wallets, balances: WalletBalances(of: wallets, asOf: today))
    }

    @Test func walletsCountedInTheTotalAreListedApartFromThoseLeftOut() {
        let checking = context.addWallet("Checking")
        let brokerage = context.addWallet("Brokerage", includeInTotal: false)
        let cash = context.addWallet("Cash")
        let pension = context.addWallet("Pension", includeInTotal: false)

        let choices = choices([checking, brokerage, cash, pension])

        #expect(choices.includedInTotal.map(\.selection) == [.wallet(checking), .wallet(cash)])
        #expect(choices.notInTotal.map(\.selection) == [.wallet(brokerage), .wallet(pension)])
    }

    @Test func archivedAndDeletedWalletsAreNotListed() throws {
        let checking = context.addWallet("Checking")
        let oldBank = context.addWallet("Old bank")
        try oldBank.archive(today: today)
        let closed = context.addWallet("Closed")
        try closed.delete(today: TestStore.today)

        let choices = choices([checking, oldBank, closed])

        #expect(choices.includedInTotal.map(\.selection) == [.wallet(checking)])
        // Every wallet still listed counts in the Total, so there is no "Not in total" section.
        #expect(choices.notInTotal.isEmpty)
    }

    @Test func eachRowShowsItsBalanceTodayInItsOwnCurrency() {
        let checking = context.addWallet("Checking")
        let cash = context.addWallet("Cash")
        let brokerage = context.addWallet("Brokerage", includeInTotal: false)
        let euros = context.addWallet("Euros", currencyCode: "EUR", includeInTotal: false)
        record(100_00, in: checking)
        record(-900_00, in: checking, on: CalendarDay(year: 2026, month: 11, day: 1))
        record(25_00, in: cash)
        record(300_00, in: brokerage)
        record(40_00, in: euros)

        let choices = choices([checking, cash, brokerage, euros])

        // The Total card: checking and cash, not the rent due next month nor the wallets left out.
        #expect(choices.total.selection == .total)
        #expect(choices.total.balance == [Money(cents: 125_00)])
        #expect(choices.includedInTotal.map(\.balance) == [[Money(cents: 100_00)], [Money(cents: 25_00)]])
        #expect(choices.notInTotal.map(\.balance) == [[Money(cents: 300_00)], [Money(cents: 40_00, currencyCode: "EUR")]])
    }

    @Test func theTotalAddsEachCurrencyUpOnItsOwn() {
        let checking = context.addWallet("Checking")
        let euros = context.addWallet("Euros", currencyCode: "EUR")
        record(100_00, in: checking)
        record(40_00, in: euros)

        let choices = choices([checking, euros])

        #expect(choices.total.balance == [Money(cents: 40_00, currencyCode: "EUR"), Money(cents: 100_00)])
        #expect(choices.total.balance.formatted(locale: Locale(identifier: "en_US")) == "€40.00, $100.00")
    }

    @Test func aTotalOfNothingIsNothingInTheWalletsCurrency() {
        let euros = context.addWallet("Euros", currencyCode: "EUR")

        let choices = choices([euros])

        #expect(choices.total.balance == [Money(cents: 0, currencyCode: "EUR")])
        #expect(choices.total.balance.formatted(locale: Locale(identifier: "en_US")) == "€0.00")
    }
}
