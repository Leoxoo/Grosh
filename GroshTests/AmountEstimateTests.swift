import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The estimate a varying Bill's transactions start at: the average of the last twelve usable transactions filed under
/// its category, or under its subcategories when the parent is chosen.
@MainActor
@Suite(.namedInTheLog)
struct AmountEstimateTests {
    private let store: TestStore
    private var context: ModelContext { store.context }

    init() throws {
        store = try TestStore()
    }

    /// Records an expense of `cents` under `category` on `day`, paid from `wallet`. `configure` sets its flags.
    @discardableResult
    private func record(
        _ cents: Int, under category: Grosh.Category, on day: CalendarDay,
        from wallet: Wallet? = nil, configure: (Transaction) -> Void = { _ in }
    ) -> Transaction {
        let transaction = context.record(-cents, on: day, in: wallet ?? store.checking, under: category)
        configure(transaction)
        return transaction
    }

    @Test func noUsableTransactionsGivesNoEstimate() throws {
        let utilities = context.addCategory("Utilities")

        #expect(try store.estimate(for: utilities) == nil)
    }

    @Test func theEstimateIsTheAverageSizeOfTheTransactions() throws {
        let utilities = context.addCategory("Utilities")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(2_000, under: utilities, on: day(2026, 9, 2))
        record(3_000, under: utilities, on: day(2026, 9, 3))

        #expect(try store.estimate(for: utilities) == 2_000)
    }

    @Test func onlyTheLastTwelveUsableTransactionsCount() throws {
        let utilities = context.addCategory("Utilities")
        // The oldest of thirteen is far larger, so it would move the average if it were counted.
        record(100_000, under: utilities, on: day(2026, 9, 1))
        for dayOfMonth in 2...13 {
            record(1_000, under: utilities, on: day(2026, 9, dayOfMonth))
        }

        #expect(try store.estimate(for: utilities) == 1_000)
    }

    @Test func aParentCountsItsSubcategoriesAndASubcategoryOnlyItself() throws {
        let utilities = context.addCategory("Utilities")
        let water = context.addCategory("Water", parent: utilities)
        let groceries = context.addCategory("Groceries")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(3_000, under: water, on: day(2026, 9, 2))
        record(50_000, under: groceries, on: day(2026, 9, 3))

        #expect(try store.estimate(for: utilities) == 2_000)
        #expect(try store.estimate(for: water) == 3_000)
    }

    @Test func estimatedExcludedAndDeletedTransactionsDoNotCount() throws {
        let utilities = context.addCategory("Utilities")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(90_000, under: utilities, on: day(2026, 9, 2)) { $0.isEstimated = true }
        record(90_000, under: utilities, on: day(2026, 9, 3)) { $0.isExcludedFromReport = true }
        record(90_000, under: utilities, on: day(2026, 9, 4)) { made in made.changeCounted { $0.deletedAt = Date.now } }

        #expect(try store.estimate(for: utilities) == 1_000)
    }

    @Test func transactionsInAnotherCurrencyDoNotCount() throws {
        let utilities = context.addCategory("Utilities")
        let euro = context.addWallet("Euro", currencyCode: "EUR")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(90_000, under: utilities, on: day(2026, 9, 2), from: euro)

        #expect(try store.estimate(for: utilities) == 1_000)
        #expect(try store.estimate(for: utilities, currencyCode: "EUR") == 90_000)
    }

    @Test func theAverageIsTakenAcrossEveryWalletInTheCurrency() throws {
        let utilities = context.addCategory("Utilities")
        let savings = context.addWallet("Savings")
        record(1_000, under: utilities, on: day(2026, 9, 1))
        record(3_000, under: utilities, on: day(2026, 9, 2), from: savings)

        #expect(try store.estimate(for: utilities) == 2_000)
    }

    @Test func transactionsOutsideTheCategoryDoNotCount() throws {
        let utilities = context.addCategory("Utilities")
        let groceries = context.addCategory("Groceries")
        record(50_000, under: groceries, on: day(2026, 9, 1))

        #expect(try store.estimate(for: utilities) == nil)
    }
}
