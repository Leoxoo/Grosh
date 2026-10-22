import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Opening a store made before people (ADR-0009): the With names typed then become one Person each, ignoring case, and
/// no transaction loses its With.
@MainActor
struct WithMigrationTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private let day = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// A transaction as an older version saved it: with a typed With name and no Person, entered `minutesAgo` before
    /// now.
    @discardableResult
    private func legacy(_ name: String, minutesAgo: Double = 0) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: -30_00), day: day, wallet: nil, category: nil)
        transaction.createdAt = Date.now.addingTimeInterval(-minutesAgo * 60)
        transaction.withName = name
        context.insert(transaction)
        transaction.wallet = store.wallet
        try context.save()
        return transaction
    }

    private func everyone() throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }

    @Test func eachDistinctNameBecomesOnePersonIgnoringCase() throws {
        let first = try legacy("Pasha", minutesAgo: 40)
        let second = try legacy("Anna", minutesAgo: 30)
        let third = try legacy("pasha", minutesAgo: 20)
        let fourth = try legacy("PASHA", minutesAgo: 10)

        try Person.migrateWithNames(in: context)

        let people = try everyone()
        #expect(people.map { $0.name.lowercased() } == ["anna", "pasha"])
        let pasha = try #require(people.last)
        #expect(Set(pasha.transactions ?? []) == [first, third, fourth])
        #expect(try #require(people.first).transactions == [second])
    }

    @Test func aPersonIsSpelledAsTheirNewestTransactionSpellsThemAndLastUsedWhenItWasEntered() throws {
        try legacy("pasha", minutesAgo: 30)
        let newest = try legacy("PASHA", minutesAgo: 5)
        try legacy("Pasha", minutesAgo: 60)

        try Person.migrateWithNames(in: context)

        let pasha = try #require(try everyone().first)
        #expect(try everyone().count == 1)
        #expect(pasha.name == "PASHA")
        #expect(pasha.lastUsedAt == newest.createdAt)
    }

    @Test func noTransactionLosesItsWith() throws {
        let transactions = [
            try legacy("Pasha", minutesAgo: 3), try legacy("pasha", minutesAgo: 2), try legacy("Anna", minutesAgo: 1),
        ]

        try Person.migrateWithNames(in: context)

        for transaction in transactions {
            #expect(transaction.orderedPeople.count == 1)
            #expect(transaction.withName == transaction.orderedPeople.first?.name)
        }
        #expect(transactions[0].orderedPeople == transactions[1].orderedPeople)
        #expect(transactions[0].withName == transactions[1].withName)
        #expect(transactions[2].withName == "Anna")
    }

    @Test func aTransactionInRecentlyDeletedKeepsItsWithToo() throws {
        let deleted = try legacy("Olga")
        deleted.deletedAt = .now

        try Person.migrateWithNames(in: context)

        #expect(deleted.orderedPeople.map(\.name) == ["Olga"])
        #expect(deleted.withName == "Olga")
    }

    @Test func aTransactionWithoutAWithGetsNoPerson() throws {
        let plain = try legacy("")
        try legacy("Anna")

        try Person.migrateWithNames(in: context)

        #expect(plain.orderedPeople.isEmpty)
        #expect(plain.withName.isEmpty)
        #expect(try everyone().map(\.name) == ["Anna"])
    }

    @Test func theMigrationIsSaved() throws {
        try legacy("Anna")
        try context.save()

        try Person.migrateWithNames(in: context)

        #expect(!context.hasChanges)
    }

    @Test func aStoreWithPeopleAlreadyIsLeftAlone() throws {
        try legacy("Anna")
        try Person.migrateWithNames(in: context)
        let typedSince = try legacy("Ivan")

        try Person.migrateWithNames(in: context)

        #expect(try everyone().map(\.name) == ["Anna"])
        #expect(typedSince.orderedPeople.isEmpty)
    }

    @Test func aStoreWithNoWithNamesGetsNoPeople() throws {
        try legacy("")

        try Person.migrateWithNames(in: context)

        #expect(try everyone().isEmpty)
    }

    @Test func migratedPeopleAreListedInPreviousMostRecentlyUsedFirst() throws {
        try legacy("Anna", minutesAgo: 30)
        try legacy("Ivan", minutesAgo: 10)
        try legacy("Olga", minutesAgo: 20)

        try Person.migrateWithNames(in: context)

        #expect(try context.fetch(Person.previous).map(\.name) == ["Ivan", "Olga", "Anna"])
    }
}
