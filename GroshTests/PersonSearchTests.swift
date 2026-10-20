import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Search finds the name of any Person in a transaction's With, and the With filter keeps the transactions that have a
/// Person among them (ADR-0009).
@MainActor
struct PersonSearchTests {
    private let fixture: CategoryFixture
    private var context: ModelContext { fixture.context }
    private let anna: Person
    private let ivan: Person
    private let olga: Person
    private let dinner: Transaction
    private let lunch: Transaction
    private let coffee: Transaction
    private let taxi: Transaction

    init() throws {
        let fixture = try CategoryFixture()
        let context = fixture.context
        let wallet = fixture.wallet
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        let olga = try Person.add(named: "Olga", in: context)
        func record(_ note: String, with people: [Person]) -> Transaction {
            let transaction = Transaction(
                amount: Money(cents: -10_00), day: CalendarDay(year: 2026, month: 10, day: 1), wallet: nil,
                category: nil, note: note
            )
            context.insert(transaction)
            transaction.wallet = wallet
            transaction.setPeople(people)
            return transaction
        }
        self.dinner = record("dinner", with: [anna, ivan])
        self.lunch = record("lunch", with: [olga])
        self.coffee = record("coffee", with: [anna])
        self.taxi = record("taxi", with: [])
        try context.save()
        self.fixture = fixture
        self.anna = anna
        self.ivan = ivan
        self.olga = olga
    }

    private var all: [Transaction] { [dinner, lunch, coffee, taxi] }

    private func notes(matching filter: TransactionFilter) -> [String] {
        all.matching(filter).map(\.note)
    }

    // MARK: Search

    @Test func searchFindsAnyPersonOnATransaction() {
        #expect(notes(matching: TransactionFilter(searchText: "ivan")) == ["dinner"])
        #expect(notes(matching: TransactionFilter(searchText: "ANNA")) == ["dinner", "coffee"])
        #expect(notes(matching: TransactionFilter(searchText: "olg")) == ["lunch"])
    }

    @Test func searchStillFindsNotes() {
        #expect(notes(matching: TransactionFilter(searchText: "taxi")) == ["taxi"])
    }

    @Test func searchFindsAPersonWhoIsHiddenSince() throws {
        try ivan.hide()

        #expect(notes(matching: TransactionFilter(searchText: "ivan")) == ["dinner"])
    }

    // MARK: The With filter

    @Test func theWithFilterKeepsTransactionsWithThePersonAmongTheirPeople() {
        #expect(notes(matching: TransactionFilter(person: anna)) == ["dinner", "coffee"])
        #expect(notes(matching: TransactionFilter(person: ivan)) == ["dinner"])
        #expect(notes(matching: TransactionFilter(person: olga)) == ["lunch"])
    }

    @Test func theWithFilterAndSearchTextNarrowEachOther() {
        #expect(notes(matching: TransactionFilter(searchText: "coffee", person: anna)) == ["coffee"])
        #expect(notes(matching: TransactionFilter(searchText: "lunch", person: anna)).isEmpty)
    }

    @Test func theWithFilterKeepsAHiddenPersonsHistory() throws {
        try anna.hide()

        #expect(notes(matching: TransactionFilter(person: anna)) == ["dinner", "coffee"])
    }

    @Test func theWithFilterIsOneOfTheFiltersAndClears() {
        var filter = TransactionFilter(searchText: "x", person: anna)

        #expect(filter.hasFilters)
        #expect(filter.isOn)
        #expect(filter != TransactionFilter(searchText: "x", person: ivan))
        #expect(filter == TransactionFilter(searchText: "x", person: anna))

        filter.clearFilters()

        #expect(filter.person == nil)
        #expect(!filter.hasFilters)
        #expect(filter.searchText == "x")
    }

    @Test func aTransactionMatchesTheFilterThroughTheSingleTransactionCheckToo() {
        let filter = TransactionFilter(person: olga)

        #expect(filter.matches(lunch))
        #expect(!filter.matches(dinner))
    }
}
