import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Transactions tab viewed by category: the period's transactions grouped under the category each is filed
/// under, with each category's total.
@MainActor
struct TransactionCategoryGroupTests {
    private let store: CategoryFixture

    init() throws {
        store = try CategoryFixture()
    }

    private func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    /// Records a transaction entered `enteredAt` seconds into the test's clock.
    @discardableResult
    private func record(
        _ note: String, _ cents: Int, under category: Grosh.Category?, on day: CalendarDay, enteredAt seconds: Double = 0
    ) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil, note: note)
        store.context.insert(transaction)
        transaction.wallet = store.wallet
        transaction.category = category
        transaction.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
        return transaction
    }

    @Test func transactionsAreGroupedUnderTheirCategoryWithItsTotal() throws {
        let cafe = try store.category("Café")
        let restaurants = try store.category("Restaurants")
        let transactions = [
            record("latte", -4_50, under: cafe, on: day(10, 1)),
            record("dinner", -60_00, under: restaurants, on: day(10, 2)),
            record("espresso", -3_00, under: cafe, on: day(10, 3)),
        ]

        let groups = TransactionCategoryGroup.groups(of: transactions)

        #expect(groups.map(\.category) == [restaurants, cafe])
        #expect(groups.map(\.total) == [Money(cents: -60_00), Money(cents: -7_50)])
    }

    @Test func moneyInComesFirstLargestFirstThenSpendingLargestFirst() throws {
        let salary = try store.category("Salary", .income)
        let tips = try store.category("Tips", .income)
        let rentals = try store.category("Rentals")
        let cafe = try store.category("Café")
        let transactions = [
            record("coffee", -4_50, under: cafe, on: day(10, 1)),
            record("tips", 40_00, under: tips, on: day(10, 1)),
            record("rent", -900_00, under: rentals, on: day(10, 1)),
            record("pay", 3_000_00, under: salary, on: day(10, 1)),
        ]

        let groups = TransactionCategoryGroup.groups(of: transactions)

        #expect(groups.map(\.category) == [salary, tips, rentals, cafe])
    }

    @Test func withinACategoryTransactionsAreInListOrder() throws {
        let cafe = try store.category("Café")
        let transactions = [
            record("Monday latte", -4_50, under: cafe, on: day(10, 5), enteredAt: 1),
            record("Wednesday espresso", -3_00, under: cafe, on: day(10, 7), enteredAt: 2),
            record("second Monday coffee", -2_00, under: cafe, on: day(10, 5), enteredAt: 3),
        ]

        let groups = TransactionCategoryGroup.groups(of: transactions)

        #expect(groups.map { $0.transactions.map(\.note) } == [
            ["Wednesday espresso", "second Monday coffee", "Monday latte"],
        ])
    }

    @Test func transactionsFiledUnderNoCategoryShareOneGroup() throws {
        let cafe = try store.category("Café")
        let transactions = [
            record("mystery", -10_00, under: nil, on: day(10, 1)),
            record("latte", -4_50, under: cafe, on: day(10, 1)),
            record("another mystery", -5_00, under: nil, on: day(10, 2)),
        ]

        let groups = TransactionCategoryGroup.groups(of: transactions)

        #expect(groups.map(\.category) == [nil, cafe])
        #expect(groups.first?.total == Money(cents: -15_00))
    }

    @Test func theCategoryTotalsAddUpToThePeriodsDifferenceExcludedTransactionsIncluded() throws {
        let salary = try store.category("Salary", .income)
        let cafe = try store.category("Café")
        let refund = record("refund", 20_00, under: cafe, on: day(10, 3))
        refund.isExcludedFromReport = true
        let transactions = [
            record("pay", 3_000_00, under: salary, on: day(10, 1)),
            record("latte", -4_50, under: cafe, on: day(10, 2)),
            refund,
        ]

        let groups = TransactionCategoryGroup.groups(of: transactions)

        #expect(groups.map(\.total) == [Money(cents: 3_000_00), Money(cents: 15_50)])
    }
}
