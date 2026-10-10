import Foundation
import SwiftData
import Testing
@testable import Grosh

/// "Suggest defaults": where every starting value of the Add Transaction sheet comes from.
@MainActor
struct SuggestDefaultsTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
    }

    private func addWallet(_ name: String) throws -> Wallet {
        try Wallet.create(name: name, startingBalance: Money(cents: 10_000), on: today, in: context)
    }

    /// Records a Café expense in `wallet`, entered at `minutesAgo` before now.
    private func spend(in wallet: Wallet, minutesAgo: Double) throws {
        let cafe = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Café" })
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = wallet
        draft.amount = Money(cents: 450)
        draft.category = cafe
        let transaction = try Transaction.create(draft, in: context)
        transaction.createdAt = Date.now.addingTimeInterval(-minutesAgo * 60)
    }

    @Test func aReminderTurnedOnStartsAWeekFromToday() {
        #expect(TransactionDefaults.reminderDay(from: today) == CalendarDay(year: 2026, month: 10, day: 16))
        #expect(TransactionDefaults.reminderDay(from: CalendarDay(year: 2026, month: 12, day: 28))
            == CalendarDay(year: 2027, month: 1, day: 4))
    }

    @Test func aNewTransactionStartsAsAnExpenseTodayWithNothingElseFilledIn() throws {
        let suggested = TransactionDefaults.suggest(on: today, in: context)

        #expect(suggested.type == .expense)
        #expect(suggested.day == today)
        #expect(suggested.wallet == nil)
        #expect(suggested.amount == Money(cents: 0))
        #expect(suggested.category == nil)
        #expect(suggested.card == nil)
        #expect(suggested.note.isEmpty)
        #expect(suggested.withName.isEmpty)
        #expect(!suggested.isExcludedFromReport)
    }

    @Test func theWalletIsTheLastUsedOne() throws {
        let checking = try addWallet("Checking")
        let cash = try addWallet("Cash")
        try spend(in: cash, minutesAgo: 10)
        try spend(in: checking, minutesAgo: 5)

        #expect(TransactionDefaults.suggest(on: today, in: context).wallet == checking)
    }

    @Test func beforeAnyUseItIsTheFirstWalletInTheUsersOrder() throws {
        let checking = try addWallet("Checking")
        _ = try addWallet("Cash") // its Starting balance was entered last, but doesn't count as use

        #expect(TransactionDefaults.suggest(on: today, in: context).wallet == checking)
    }

    @Test func anArchivedWalletIsNeverSuggested() throws {
        let checking = try addWallet("Checking")
        let cash = try addWallet("Cash")
        try spend(in: checking, minutesAgo: 10)
        try spend(in: cash, minutesAgo: 5)
        try cash.archive()

        #expect(TransactionDefaults.suggest(on: today, in: context).wallet == checking)
    }

    @Test func whenOnlyArchivedWalletsWereUsedItIsTheFirstUnarchivedWallet() throws {
        let checking = try addWallet("Checking")
        let cash = try addWallet("Cash")
        try spend(in: cash, minutesAgo: 5)
        try cash.archive()

        #expect(TransactionDefaults.suggest(on: today, in: context).wallet == checking)
    }
}
