import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Home's Recent transactions.
@MainActor
struct RecentTransactionsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        checking = Wallet(name: "Checking")
        container.mainContext.insert(checking)
    }

    private func record(_ note: String, on day: CalendarDay, enteredAt seconds: Double) {
        let transaction = Transaction(amount: Money(cents: -1_00), day: day, wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = checking
        transaction.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }

    @Test func recentTransactionsAreTheLatestDatedTodayOrEarlierNewestFirst() throws {
        record("last week", on: CalendarDay(year: 2026, month: 10, day: 2), enteredAt: 1)
        record("yesterday", on: CalendarDay(year: 2026, month: 10, day: 8), enteredAt: 2)
        record("rent due", on: CalendarDay(year: 2026, month: 11, day: 1), enteredAt: 3)
        record("this morning", on: today, enteredAt: 4)
        record("just now", on: today, enteredAt: 5)
        record("forgot one from yesterday", on: CalendarDay(year: 2026, month: 10, day: 8), enteredAt: 6)

        let recent = try context.fetch(Transaction.recent(limit: 4, asOf: today))

        #expect(recent.map(\.note) == ["just now", "this morning", "forgot one from yesterday", "yesterday"])
    }
}
