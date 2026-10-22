import Foundation
import SwiftData
import Testing
@testable import Grosh

/// People in With (ADR-0009): a Person is a name with an optional phone, a hidden flag and a last-used date; a
/// transaction is with any number of them, except a Loan or Debt, which is with exactly one. Typing a name makes the
/// Person or reuses the one who has it, ignoring case.
@MainActor
struct PersonTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    private func everyone() throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    private func person(_ name: String, lastUsed: Date = .now) throws -> Person {
        let person = Person(name: name, lastUsedAt: lastUsed)
        context.insert(person)
        try context.save()
        return person
    }

    /// The names of the people the With menu lists in Previous.
    private func previousNames() throws -> [String] {
        try context.fetch(Person.previous).map(\.name)
    }

    /// An Expense with `people`, saved through the Add sheet's draft.
    @discardableResult
    private func eat(with people: [Person]) throws -> Transaction {
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = store.wallet
        draft.amount = Money(cents: 30_00)
        draft.category = try store.category("Restaurants")
        draft.people = people
        return try Transaction.create(draft, in: context)
    }

    /// A draft for a Loan of 100.00, with `people`.
    private func loanDraft(with people: [Person]) throws -> TransactionDraft {
        var draft = TransactionDraft(type: .debtLoan, day: today)
        draft.wallet = store.wallet
        draft.amount = Money(cents: 100_00)
        draft.category = try context.lockedCategory(.loan)
        draft.people = people
        return draft
    }

    // MARK: The model (ADR-0001)

    @Test func aPersonIsInTheStoreWithDefaultsForEverythingButItsName() throws {
        #expect(GroshStore.schema.entities.contains { $0.name == "Person" })

        let anna = Person(name: "Anna")

        #expect(anna.phone == nil)
        #expect(!anna.isHidden)
        #expect(anna.contactIdentifier == nil)
        #expect(anna.transactions?.isEmpty == true)
        #expect(abs(anna.lastUsedAt.timeIntervalSinceNow) < 60)
    }

    @Test func aPersonIsSavedWithItsPhoneHiddenFlagAndLastUsedDate() throws {
        let lastUsed = Date(timeIntervalSince1970: 1_700_000_000)
        let anna = Person(name: "Anna", phone: "555-0100", lastUsedAt: lastUsed)
        anna.isHidden = true
        context.insert(anna)
        try context.save()

        let saved = try #require(try everyone().first)
        #expect(saved.name == "Anna")
        #expect(saved.phone == "555-0100")
        #expect(saved.isHidden)
        #expect(saved.lastUsedAt == lastUsed)
    }

    // MARK: Typing a name

    @Test func typingANewNameMakesAPerson() throws {
        let anna = try Person.add(named: "  Anna ", in: context)

        #expect(anna.name == "Anna")
        #expect(try everyone().map(\.name) == ["Anna"])
        #expect(!context.hasChanges)
    }

    @Test func typingANameAgainIgnoringCaseReusesThePerson() throws {
        let pasha = try Person.add(named: "Pasha", in: context)

        let again = try Person.add(named: " pASHA", in: context)

        #expect(again === pasha)
        #expect(try everyone().map(\.name) == ["Pasha"])
    }

    @Test(arguments: ["", "   ", "\n"])
    func aNameOfNothingIsRefused(name: String) throws {
        #expect(throws: PersonRuleError.missingName) { try Person.add(named: name, in: context) }
        #expect(try everyone().isEmpty)
    }

    @Test func aNewPersonKeepsThePhoneAddedWithThem() throws {
        let anna = try Person.add(named: "Anna", phone: " 555-0100 ", in: context)

        #expect(anna.phone == "555-0100")
    }

    @Test(arguments: [nil, "", "  "] as [String?])
    func aNewPersonAddedWithoutAPhoneHasNone(phone: String?) throws {
        let anna = try Person.add(named: "Anna", phone: phone, in: context)

        #expect(anna.phone == nil)
    }

    @Test func addingAnExistingNameLeavesThePhoneTheyHave() throws {
        try Person.add(named: "Anna", phone: "555-0100", in: context)

        let again = try Person.add(named: "anna", phone: "555-0199", in: context)

        #expect(again.phone == "555-0100")
    }

    // MARK: Several people

    @Test func aTransactionCanBeWithSeveralPeople() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)

        let dinner = try eat(with: [ivan, anna])

        #expect(dinner.orderedPeople.map(\.name) == ["Anna", "Ivan"])
        #expect(dinner.withName == "Anna; Ivan")
        #expect(anna.transactions == [dinner])
        #expect(ivan.transactions == [dinner])
    }

    @Test func aPersonChosenTwiceIsInWithOnce() throws {
        let anna = try Person.add(named: "Anna", in: context)

        let dinner = try eat(with: [anna, anna])

        #expect(dinner.orderedPeople.count == 1)
        #expect(dinner.withName == "Anna")
    }

    @Test func editingATransactionChangesItsPeople() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        let olga = try Person.add(named: "Olga", in: context)
        let dinner = try eat(with: [anna, ivan])

        var editing = TransactionDraft(editing: dinner)
        #expect(Set(editing.people.map(\.name)) == ["Anna", "Ivan"])
        editing.people = [ivan, olga]
        try dinner.update(with: editing)

        #expect(dinner.orderedPeople.map(\.name) == ["Ivan", "Olga"])
        #expect(dinner.withName == "Ivan; Olga")
        #expect(anna.transactions?.isEmpty == true)
    }

    @Test func duplicatingATransactionKeepsItsPeople() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        let dinner = try eat(with: [anna, ivan])

        let copy = try Transaction.create(TransactionDraft(duplicating: dinner, on: today), in: context)

        #expect(copy.orderedPeople.map(\.name) == ["Anna", "Ivan"])
        #expect(anna.transactions?.count == 2)
    }

    @Test func deletingATransactionLeavesItsPeople() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let dinner = try eat(with: [anna])

        context.delete(dinner)
        try context.save()

        #expect(try everyone().map(\.name) == ["Anna"])
    }

    // MARK: A Loan or Debt is with one Person

    @Test func aLoanOrDebtNeedsAPerson() throws {
        let draft = try loanDraft(with: [])

        #expect(draft.isMissingWith)
        #expect(!draft.canSave)
        #expect(throws: TransactionRuleError.missingWith) { try Transaction.create(draft, in: context) }
    }

    @Test func aLoanOrDebtWithOnePersonCanBeSaved() throws {
        let pasha = try Person.add(named: "Pasha", in: context)

        let loan = try Transaction.create(try loanDraft(with: [pasha]), in: context)

        #expect(loan.orderedPeople == [pasha])
        #expect(loan.withName == "Pasha")
    }

    @Test func aLoanOrDebtWithSeveralPeopleIsRefused() throws {
        var draft = try loanDraft(with: [])
        draft.people = [try Person.add(named: "Pasha", in: context), try Person.add(named: "Anna", in: context)]

        #expect(!draft.canSave)
        #expect(throws: TransactionRuleError.tooManyWith) { try Transaction.create(draft, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func anExpenseNeedsNoPerson() throws {
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = store.wallet
        draft.amount = Money(cents: 30_00)
        draft.category = try store.category("Restaurants")

        #expect(draft.canSave)
        #expect(!draft.isMissingWith)
    }

    @Test func choosingALoanOrDebtCategoryKeepsOnlyTheFirstPerson() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        var draft = TransactionDraft(type: .expense, day: today)
        draft.people = [ivan, anna]

        draft.type = .debtLoan
        draft.category = try context.lockedCategory(.debt)

        #expect(draft.people == [ivan])
    }

    @Test func theMenuTakesOnePersonForALoanOrDebtAndSeveralForAnythingElse() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)

        var one: [Person] = []
        one.choose(anna, picksOne: true)
        one.choose(ivan, picksOne: true)
        #expect(one == [ivan])
        one.choose(ivan, picksOne: true)
        #expect(one == [ivan])

        var several: [Person] = []
        several.choose(anna, picksOne: false)
        several.choose(ivan, picksOne: false)
        #expect(several == [anna, ivan])
        several.choose(anna, picksOne: false)
        #expect(several == [ivan])
    }

    // MARK: Last used

    @Test func choosingAPersonOnATransactionMakesThemTheMostRecentlyUsed() throws {
        let longAgo = Date(timeIntervalSince1970: 1_000_000_000)
        let anna = try person("Anna", lastUsed: longAgo)
        let ivan = try person("Ivan", lastUsed: longAgo)

        try eat(with: [anna])

        #expect(abs(anna.lastUsedAt.timeIntervalSinceNow) < 60)
        #expect(ivan.lastUsedAt == longAgo)
    }

    @Test func addingAPersonByNameMakesThemTheMostRecentlyUsed() throws {
        let longAgo = Date(timeIntervalSince1970: 1_000_000_000)
        let anna = try person("Anna", lastUsed: longAgo)

        try Person.add(named: "anna", in: context)

        #expect(abs(anna.lastUsedAt.timeIntervalSinceNow) < 60)
    }

    @Test func aPersonIsNeverMadeLessRecentByAnOlderUse() throws {
        let recent = Date(timeIntervalSince1970: 1_700_000_000)
        let anna = try person("Anna", lastUsed: recent)

        anna.markUsed(at: recent.addingTimeInterval(-86_400))
        #expect(anna.lastUsedAt == recent)

        anna.markUsed(at: recent.addingTimeInterval(86_400))
        #expect(anna.lastUsedAt == recent.addingTimeInterval(86_400))
    }

    // MARK: Previous

    @Test func previousListsEveryoneWhoIsntHiddenMostRecentlyUsedFirst() throws {
        let now = Date.now
        try person("Anna", lastUsed: now.addingTimeInterval(-300))
        try person("Ivan", lastUsed: now.addingTimeInterval(-100))
        try person("Olga", lastUsed: now.addingTimeInterval(-200))
        let pasha = try person("Pasha", lastUsed: now)
        try context.save()
        try pasha.hide()

        #expect(try previousNames() == ["Ivan", "Olga", "Anna"])
    }

    @Test func peopleUsedAtTheSameTimeAreListedByName() throws {
        let now = Date.now
        try person("Olga", lastUsed: now)
        try person("Anna", lastUsed: now)
        try person("Ivan", lastUsed: now)
        try context.save()

        #expect(try previousNames() == ["Anna", "Ivan", "Olga"])
    }

    @Test func searchingNarrowsPreviousToNamesContainingWhatWasTyped() throws {
        let now = Date.now
        let people = [
            try person("Anna", lastUsed: now.addingTimeInterval(-3)),
            try person("Ivan", lastUsed: now.addingTimeInterval(-2)),
            try person("José", lastUsed: now.addingTimeInterval(-1)),
        ]

        #expect(PreviousPeople(people, typed: "").people.map(\.name) == ["Anna", "Ivan", "José"])
        #expect(PreviousPeople(people, typed: " AN ").people.map(\.name) == ["Anna", "Ivan"])
        #expect(PreviousPeople(people, typed: "jose").people.map(\.name) == ["José"])
        #expect(PreviousPeople(people, typed: "zzz").people.isEmpty)
    }

    @Test func theMenuOffersToAddWhatWasTypedUnlessAPersonHasExactlyThatName() throws {
        let people = [try person("Anna"), try person("Ivan")]

        #expect(PreviousPeople(people, typed: "").addableName == nil)
        #expect(PreviousPeople(people, typed: "   ").addableName == nil)
        #expect(PreviousPeople(people, typed: " Olga ").addableName == "Olga")
        #expect(PreviousPeople(people, typed: "zzz").people.isEmpty)
        #expect(PreviousPeople(people, typed: "ann").addableName == "ann")
        #expect(PreviousPeople(people, typed: "ANNA").addableName == nil)
    }

    @Test func addingFromTheMenuMakesTheNewPersonTheFirstInPrevious() throws {
        let anna = try Person.add(named: "Anna", in: context)
        anna.lastUsedAt = Date(timeIntervalSince1970: 1_000_000_000)

        let olga = try Person.add(named: "Olga", phone: "555-0100", in: context)

        #expect(try previousNames() == ["Olga", "Anna"])
        #expect(olga.phone == "555-0100")
    }

    // MARK: Hide

    @Test func aHiddenPersonLeavesPreviousButKeepsTheirNameAndHistory() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        let dinner = try eat(with: [anna, ivan])

        try anna.hide()

        #expect(try previousNames() == ["Ivan"])
        #expect(anna.isHidden)
        #expect(anna.name == "Anna")
        #expect(dinner.orderedPeople.map(\.name) == ["Anna", "Ivan"])
        #expect(dinner.withName == "Anna; Ivan")
        #expect(anna.transactions == [dinner])
    }

    @Test func hidingIsSaved() throws {
        let anna = try Person.add(named: "Anna", in: context)

        try anna.hide()

        #expect(!context.hasChanges)
    }

    @Test func typingAHiddenPersonsNameAgainBringsThemBack() throws {
        let anna = try Person.add(named: "Anna", in: context)
        try anna.hide()
        #expect(try previousNames().isEmpty)
        #expect(PreviousPeople([], typed: "anna").addableName == "anna")

        let again = try Person.add(named: "anna", in: context)

        #expect(again === anna)
        #expect(!anna.isHidden)
        #expect(try previousNames() == ["Anna"])
        #expect(try everyone().count == 1)
    }

    @Test func aHiddenPersonKeepsAPlaceOnTheTransactionsEditedAfterwards() throws {
        let anna = try Person.add(named: "Anna", in: context)
        let dinner = try eat(with: [anna])
        try anna.hide()

        var editing = TransactionDraft(editing: dinner)
        editing.note = "Dessert"
        try dinner.update(with: editing)

        #expect(dinner.orderedPeople == [anna])
        #expect(anna.isHidden)
    }
}
