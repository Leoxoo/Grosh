import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The estimate a varying Bill's transactions start at: the average of the last twelve usable transactions filed under
/// its category, or under its subcategories when the parent is chosen.
@MainActor
struct AmountEstimateTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }

    init() throws {
        store = try CategoryFixture()
    }

    /// An expense category, inserted, optionally under `parent`.
    private func category(_ name: String, parent: Grosh.Category? = nil) -> Grosh.Category {
        let category = Grosh.Category(name: name, type: .expense, symbolName: "bolt", color: .purple, parent: parent)
        context.insert(category)
        return category
    }

    /// Records an expense of `cents` under `category` on `day`, paid from `wallet`. `configure` sets its flags.
    @discardableResult
    private func record(
        _ cents: Int, under category: Grosh.Category, on day: CalendarDay = CalendarDay(year: 2026, month: 9, day: 1),
        from wallet: Wallet? = nil, configure: (Transaction) -> Void = { _ in }
    ) -> Transaction {
        let transaction = Transaction(
            amount: Money(cents: -cents), day: day, wallet: wallet ?? store.wallet, category: category
        )
        configure(transaction)
        context.insert(transaction)
        return transaction
    }

    /// The estimate for `category`, over every transaction in the store.
    private func estimate(for category: Grosh.Category, currencyCode: String = "USD") throws -> Int? {
        try context.save()
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        return AmountEstimate.cents(among: transactions, for: category, currencyCode: currencyCode)
    }

    @Test func noUsableTransactionsGivesNoEstimate() throws {
        let utilities = category("Utilities")

        #expect(try estimate(for: utilities) == nil)
    }

    @Test func theEstimateIsTheAverageSizeOfTheTransactions() throws {
        let utilities = category("Utilities")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(2_000, under: utilities, on: day(2026, 9, 2))
        record(3_000, under: utilities, on: day(2026, 9, 3))

        #expect(try estimate(for: utilities) == 2_000)
    }

    @Test func onlyTheLastTwelveUsableTransactionsCount() throws {
        let utilities = category("Utilities")
        // The oldest of thirteen is far larger, so it would move the average if it were counted.
        record(100_000, under: utilities, on: day(2026, 9, 1))
        for dayOfMonth in 2...13 {
            record(1_000, under: utilities, on: day(2026, 9, dayOfMonth))
        }

        #expect(try estimate(for: utilities) == 1_000)
    }

    @Test func aParentCountsItsSubcategoriesAndASubcategoryOnlyItself() throws {
        let utilities = category("Utilities")
        let water = category("Water", parent: utilities)
        let groceries = category("Groceries")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(3_000, under: water, on: day(2026, 9, 2))
        record(50_000, under: groceries, on: day(2026, 9, 3))

        #expect(try estimate(for: utilities) == 2_000)
        #expect(try estimate(for: water) == 3_000)
    }

    @Test func estimatedExcludedAndDeletedTransactionsDoNotCount() throws {
        let utilities = category("Utilities")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(90_000, under: utilities, on: day(2026, 9, 2)) { $0.isEstimated = true }
        record(90_000, under: utilities, on: day(2026, 9, 3)) { $0.isExcludedFromReport = true }
        record(90_000, under: utilities, on: day(2026, 9, 4)) { $0.deletedAt = Date.now }

        #expect(try estimate(for: utilities) == 1_000)
    }

    @Test func transactionsInAnotherCurrencyDoNotCount() throws {
        let utilities = category("Utilities")
        let euro = Wallet(name: "Euro")
        euro.currencyCode = "EUR"
        context.insert(euro)
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(90_000, under: utilities, on: day(2026, 9, 2), from: euro)

        #expect(try estimate(for: utilities) == 1_000)
        #expect(try estimate(for: utilities, currencyCode: "EUR") == 90_000)
    }

    @Test func theAverageIsTakenAcrossEveryWalletInTheCurrency() throws {
        let utilities = category("Utilities")
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(3_000, under: utilities, on: day(2026, 9, 2), from: savings)

        #expect(try estimate(for: utilities) == 2_000)
    }

    @Test func transactionsOutsideTheCategoryDoNotCount() throws {
        let utilities = category("Utilities")
        let groceries = category("Groceries")
        record(50_000, under: groceries, on: day(2026, 9, 1))

        #expect(try estimate(for: utilities) == nil)
    }
}
