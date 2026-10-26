import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Contacts in the With menu (ADR-0009): the user's contacts are read through a lookup, a picked contact is stored on a
/// Person as an identifier with a name and phone snapshot, and the snapshots are refreshed from the contact while it
/// resolves. Everything here runs on the stand-in, never on the real Contacts.
@MainActor
@Suite(.namedInTheLog)
struct PersonContactTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    private let pasha = Contact(identifier: "c-pasha", name: "Pasha", phoneNumbers: ["+1 555 0100"])
    private let anna = Contact(identifier: "c-anna", name: "Anna Lee", phoneNumbers: ["+1 555 0101", "+1 555 0102"])
    private let cafe = Contact(identifier: "c-cafe", name: "Café Roma")

    init() throws {
        store = try CategoryFixture()
    }

    private func everyone() throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    private func person(_ name: String, phone: String? = nil) throws -> Person {
        let person = Person(name: name, phone: phone)
        context.insert(person)
        try context.save()
        return person
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

    // MARK: Reading the contacts, and access

    @Test func contactsAreNotTouchedUntilTheMenuNeedsThem() {
        let contacts = RecordingContactLookup([pasha], access: .notDetermined)

        #expect(contacts.access == .notDetermined)
        #expect(contacts.calls.isEmpty)
    }

    @Test func openingTheMenuAsksForAccessOnlyWhileTheUserHasNotAnswered() async {
        let contacts = RecordingContactLookup([pasha], access: .notDetermined, answer: .authorized)

        let first = await contacts.accessForMenu()
        let second = await contacts.accessForMenu()

        #expect(first == .authorized)
        #expect(second == .authorized)
        #expect(contacts.calls == [.requestAccess])
    }

    @Test func openingTheMenuAfterTheUserAnsweredNeverAsksAgain() async {
        let contacts = RecordingContactLookup([pasha], access: .denied)

        let access = await contacts.accessForMenu()

        #expect(access == .denied)
        #expect(contacts.calls.isEmpty)
    }

    @Test func theContactsSectionIsListedOnlyForAuthorizedOrLimitedAccess() {
        #expect(ContactsAccess.authorized.showsContacts)
        #expect(ContactsAccess.limited.showsContacts)
        #expect(!ContactsAccess.denied.showsContacts)
        #expect(!ContactsAccess.notDetermined.showsContacts)
    }

    @Test func onlyLimitedAccessOffersToShareMoreContacts() {
        #expect(ContactsAccess.limited.offersToShareMore)
        #expect(!ContactsAccess.authorized.offersToShareMore)
        #expect(!ContactsAccess.denied.offersToShareMore)
    }

    @Test func searchMatchesNamesIgnoringCaseAndAccents() async {
        let contacts = RecordingContactLookup([pasha, anna, cafe])

        #expect(await contacts.search("anna") == [anna])
        #expect(await contacts.search("CAFE") == [cafe])
        #expect(await contacts.search("  lee ") == [anna])
        #expect(await contacts.search("nobody").isEmpty)
    }

    @Test func searchWithNothingTypedListsEveryContact() async {
        let contacts = RecordingContactLookup([pasha, anna, cafe])

        #expect(await contacts.search("") == [pasha, anna, cafe])
        #expect(await contacts.search("   ") == [pasha, anna, cafe])
    }

    @Test func withAccessDeniedNothingIsListedAndTheMenuStillWorksFromPrevious() async throws {
        let contacts = RecordingContactLookup([pasha], access: .denied)
        let known = try person("Anna")

        #expect(await contacts.search("").isEmpty)
        #expect(await contacts.search("Pasha").isEmpty)
        #expect(PreviousPeople([known], typed: "ann").people == [known])
        #expect(PreviousPeople([known], typed: "Pasha").addableName == "Pasha")
        #expect(try Person.add(named: "Pasha", in: context).contactIdentifier == nil)
    }

    @Test func underLimitedAccessOnlyTheSharedContactsAreListed() async {
        // The stand-in holds what the user shared; anna is in their address book but not shared.
        let contacts = RecordingContactLookup([pasha], access: .limited)

        #expect(await contacts.search("") == [pasha])
        #expect(await contacts.search("anna").isEmpty)

        contacts.book.append(anna)

        #expect(await contacts.search("anna") == [anna])
    }

    @Test func anIdentifierResolvesToTheContactsCurrentPhone() async {
        let contacts = RecordingContactLookup([pasha])

        #expect(await contacts.contact(withIdentifier: "c-pasha")?.phoneNumbers == ["+1 555 0100"])

        contacts.book = [Contact(identifier: "c-pasha", name: "Pasha", phoneNumbers: ["+1 555 0199"])]

        #expect(await contacts.contact(withIdentifier: "c-pasha")?.phoneNumbers == ["+1 555 0199"])
        #expect(await contacts.contact(withIdentifier: "c-missing") == nil)
    }

    @Test func aContactHoldsEachNumberOnceAndTrimsItsName() {
        let contact = Contact(identifier: "c", name: " Pasha ", phoneNumbers: [" 555 ", "555", "", "777"])

        #expect(contact.name == "Pasha")
        #expect(contact.phoneNumbers == ["555", "777"])
    }

    // MARK: Picking a contact

    @Test func pickingAContactStoresItsIdentifierNameAndPhoneOnThePerson() throws {
        let person = try Person.add(pasha, in: context)

        #expect(person.contactIdentifier == "c-pasha")
        #expect(person.name == "Pasha")
        #expect(person.phone == "+1 555 0100")
        #expect(try everyone().count == 1)
    }

    @Test func pickingAContactMakesThemTheMostRecentPerson() throws {
        let earlier = try person("Anna")
        earlier.lastUsedAt = Date.now.addingTimeInterval(-3600)

        try Person.add(pasha, in: context)

        #expect(try context.fetch(Person.previous).map(\.name) == ["Pasha", "Anna"])
    }

    @Test func aContactWithSeveralNumbersAsksWhichToKeep() throws {
        #expect(anna.needsPhoneChoice)
        #expect(!pasha.needsPhoneChoice)
        #expect(!cafe.needsPhoneChoice)

        let person = try Person.add(anna, phone: "+1 555 0102", in: context)

        #expect(person.phone == "+1 555 0102")
    }

    @Test func aContactWithNoNumberLeavesThePersonsOwnWhenPicked() throws {
        let known = try person("Café Roma", phone: "555 0000")

        let picked = try Person.add(cafe, in: context)

        #expect(picked === known)
        #expect(picked.phone == "555 0000")
        #expect(picked.contactIdentifier == "c-cafe")
    }

    @Test func aChosenNumberTheContactDoesNotHaveIsNotStored() throws {
        let person = try Person.add(anna, phone: "999", in: context)

        #expect(person.phone == "+1 555 0101")
    }

    @Test func aContactMatchingAPersonByNameAttachesToThemIgnoringCase() throws {
        let existing = try person("pasha", phone: "old number")
        let eaten = try eat(with: [existing])

        let picked = try Person.add(pasha, in: context)

        #expect(picked === existing)
        #expect(try everyone().count == 1)
        #expect(picked.contactIdentifier == "c-pasha")
        #expect(picked.name == "Pasha")
        #expect(picked.phone == "+1 555 0100")
        #expect(eaten.withName == "Pasha")
    }

    @Test func aContactMatchingAHiddenPersonBringsThemBack() throws {
        let hidden = try person("Pasha")
        try hidden.hide()

        let picked = try Person.add(pasha, in: context)

        #expect(picked === hidden)
        #expect(!picked.isHidden)
        #expect(try context.fetch(Person.previous).map(\.name) == ["Pasha"])
    }

    @Test func pickingTheSameContactTwiceMakesOnePerson() throws {
        let first = try Person.add(pasha, in: context)
        let second = try Person.add(pasha, in: context)

        #expect(first === second)
        #expect(try everyone().count == 1)
    }

    @Test func aContactRenamedSincePickedAttachesToItsPersonByIdentifier() throws {
        let linked = try Person.add(pasha, in: context)
        let renamed = Contact(identifier: "c-pasha", name: "Pavel", phoneNumbers: ["+1 555 0100"])

        let picked = try Person.add(renamed, in: context)

        #expect(picked === linked)
        #expect(picked.name == "Pavel")
        #expect(try everyone().count == 1)
    }

    @Test func aContactWithoutANameIsRefused() {
        #expect(throws: PersonRuleError.missingName) {
            try Person.add(Contact(identifier: "c-blank", name: "  "), in: context)
        }
    }

    // MARK: Refreshing from the contacts

    @Test func aLinkedPersonTakesTheContactsNameAndPhoneWhenTheMenuOpens() async throws {
        let linked = try Person.add(pasha, in: context)
        let contacts = RecordingContactLookup([
            Contact(identifier: "c-pasha", name: "Pavel", phoneNumbers: ["+1 555 0188"]),
        ])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.name == "Pavel")
        #expect(linked.phone == "+1 555 0188")
        #expect(linked.contactIdentifier == "c-pasha")
        #expect(try everyone().count == 1)
    }

    @Test func aRenamedContactRenamesTheWithOfEveryTransactionThePersonIsIn() async throws {
        let linked = try Person.add(pasha, in: context)
        let dinner = try eat(with: [linked, try person("Anna")])
        let deleted = try eat(with: [linked])
        deleted.deletedAt = .now
        try context.save()
        let contacts = RecordingContactLookup([Contact(identifier: "c-pasha", name: "Pavel")])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(dinner.withName == "Anna; Pavel")
        #expect(deleted.withName == "Pavel")
    }

    @Test func aPersonKeepsTheirNumberWhileTheContactStillHasIt() async throws {
        let linked = try Person.add(anna, phone: "+1 555 0102", in: context)
        let contacts = RecordingContactLookup([anna])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.phone == "+1 555 0102")
    }

    @Test func aPersonTakesTheContactsFirstNumberWhenTheirNumberIsGone() async throws {
        let linked = try Person.add(anna, phone: "+1 555 0102", in: context)
        let contacts = RecordingContactLookup([
            Contact(identifier: "c-anna", name: "Anna Lee", phoneNumbers: ["+1 555 0150", "+1 555 0151"]),
        ])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.phone == "+1 555 0150")
    }

    @Test func aContactRenamedToAnotherPersonsNameKeepsTheStoredNameButRefreshesThePhone() async throws {
        let taken = try person("Pavel")
        let linked = try Person.add(pasha, in: context)
        let contacts = RecordingContactLookup([
            Contact(identifier: "c-pasha", name: "pavel", phoneNumbers: ["+1 555 0188"]),
        ])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.name == "Pasha")
        #expect(linked.phone == "+1 555 0188")
        #expect(taken.name == "Pavel")
    }

    @Test func aDeletedContactLeavesTheStoredNameAndPhone() async throws {
        let linked = try Person.add(pasha, in: context)
        let dinner = try eat(with: [linked])
        let contacts = RecordingContactLookup([])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(contacts.calls == [.contacts(["c-pasha"])])
        #expect(linked.name == "Pasha")
        #expect(linked.phone == "+1 555 0100")
        #expect(linked.contactIdentifier == "c-pasha")
        #expect(dinner.withName == "Pasha")
    }

    @Test func aContactNotSharedUnderLimitedAccessLeavesTheStoredValues() async throws {
        let linked = try Person.add(anna, phone: "+1 555 0101", in: context)
        let contacts = RecordingContactLookup([pasha], access: .limited)

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.name == "Anna Lee")
        #expect(linked.phone == "+1 555 0101")
    }

    @Test func withAccessDeniedTheStoredValuesStayAndNothingBreaks() async throws {
        let linked = try Person.add(pasha, in: context)
        let contacts = RecordingContactLookup(
            [Contact(identifier: "c-pasha", name: "Pavel", phoneNumbers: ["+1 555 0188"])], access: .denied
        )

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.name == "Pasha")
        #expect(linked.phone == "+1 555 0100")
    }

    @Test func aContactWithNoNumberLeavesThePersonsPhoneOnRefresh() async throws {
        let linked = try Person.add(pasha, in: context)
        let contacts = RecordingContactLookup([Contact(identifier: "c-pasha", name: "Pasha")])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(linked.phone == "+1 555 0100")
    }

    @Test func peopleWithoutALinkAreNeverRefreshedAndWithNoneLinkedContactsIsNotAsked() async throws {
        let plain = try person("Pasha", phone: "555 0000")
        let contacts = RecordingContactLookup([pasha])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(contacts.calls.isEmpty)
        #expect(plain.phone == "555 0000")
        #expect(plain.contactIdentifier == nil)
    }

    @Test func refreshingOnlyAsksForTheLinkedPeoplesIdentifiers() async throws {
        try Person.add(pasha, in: context)
        try person("Anna")
        let contacts = RecordingContactLookup([pasha, anna])

        try await Person.refreshFromContacts(using: contacts, in: context)

        #expect(contacts.calls == [.contacts(["c-pasha"])])
    }
}
