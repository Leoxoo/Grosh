import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Opening a store made before people (ADR-0009): the With names typed then become one Person each, ignoring case, and
/// no transaction loses its With.
@MainActor
@Suite(.namedInTheLog)
struct WithMigrationTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private let day = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try TestStore()
    }

    /// A transaction as an older version saved it: with a typed With name and no Person, entered `minutesAgo` before
    /// now.
    @discardableResult
    private func legacy(_ name: String, minutesAgo: Double = 0) throws -> Transaction {
        let transaction = Transaction.insert(
            cents: -30_00, on: day, wallet: store.checking, category: nil, in: context
        )
        transaction.createdAt = Date.now.addingTimeInterval(-minutesAgo * 60)
        transaction.withName = name
        try context.save()
        return transaction
    }

    @Test func eachDistinctNameBecomesOnePersonIgnoringCase() throws {
        let first = try legacy("Pasha", minutesAgo: 40)
        let second = try legacy("Anna", minutesAgo: 30)
        let third = try legacy("pasha", minutesAgo: 20)
        let fourth = try legacy("PASHA", minutesAgo: 10)

        try Person.migrateWithNames(in: context)

        let people = try context.everyone()
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

        let pasha = try #require(try context.everyone().first)
        #expect(try context.everyone().count == 1)
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
        deleted.changeCounted { $0.deletedAt = .now }

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
        #expect(try context.everyone().map(\.name) == ["Anna"])
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

        #expect(try context.everyone().map(\.name) == ["Anna"])
        #expect(typedSince.orderedPeople.isEmpty)
    }

    @Test func aStoreWithNoWithNamesGetsNoPeople() throws {
        try legacy("")

        try Person.migrateWithNames(in: context)

        #expect(try context.everyone().isEmpty)
    }

    @Test func migratedPeopleAreListedInPreviousMostRecentlyUsedFirst() throws {
        try legacy("Anna", minutesAgo: 30)
        try legacy("Ivan", minutesAgo: 10)
        try legacy("Olga", minutesAgo: 20)

        try Person.migrateWithNames(in: context)

        #expect(try context.fetch(Person.previous).map(\.name) == ["Ivan", "Olga", "Anna"])
    }
}
