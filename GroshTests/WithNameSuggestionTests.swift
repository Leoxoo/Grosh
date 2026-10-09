import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The With field autocompletes from names used before.
@MainActor
struct WithNameSuggestionTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    /// Records a Restaurants expense with `name`, entered `minutesAgo` before now.
    private func eat(with name: String, minutesAgo: Double) throws {
        let restaurants = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Restaurants" })
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: 3_000)
        draft.category = restaurants
        draft.withName = name
        let transaction = try Transaction.create(draft, in: context)
        transaction.createdAt = Date.now.addingTimeInterval(-minutesAgo * 60)
    }

    @Test func suggestsNamesUsedBeforeThatContainWhatWasTyped() throws {
        try eat(with: "Anna", minutesAgo: 30)
        try eat(with: "Ivan", minutesAgo: 20)
        try eat(with: "Pasha", minutesAgo: 10)

        #expect(try Transaction.withNames(matching: "an", in: context) == ["Ivan", "Anna"])
    }

    @Test func eachNameIsSuggestedOnceMostRecentlyUsedFirst() throws {
        try eat(with: "Pasha", minutesAgo: 30)
        try eat(with: "Anna", minutesAgo: 20)
        try eat(with: "pasha", minutesAgo: 10)

        #expect(try Transaction.withNames(matching: "", in: context) == ["pasha", "Anna"])
    }

    @Test func theNameAlreadyTypedInFullIsNotSuggested() throws {
        try eat(with: "Anna", minutesAgo: 10)

        #expect(try Transaction.withNames(matching: "anna", in: context).isEmpty)
    }

    @Test func atMostTheRequestedNumberOfNamesAreSuggested() throws {
        for (minutes, name) in ["A1", "A2", "A3", "A4"].enumerated() {
            try eat(with: name, minutesAgo: Double(minutes))
        }

        #expect(try Transaction.withNames(matching: "a", limit: 2, in: context) == ["A1", "A2"])
    }
}
