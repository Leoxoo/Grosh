import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Text them (ADR-0009, ADR-0010): the message about what is owed, worded with the app's money formatting; the choice
/// between the Person's contact's live phone and the stored one; the compose sheet or, where texting is unavailable, copy
/// or share. The Messages sheet itself never sends: it only opens prefilled, and the user taps Send.
@MainActor
struct TextReminderTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private let dinnerDay = day(2026, 10, 3)

    init() throws {
        fixture = try ExpectationFixture()
    }

    private func text(
        _ name: String = "Alex", phone: String? = nil, contact: String? = nil, owesYou: [Money] = [],
        youOwe: [Money] = [], expense: String? = nil
    ) -> TextReminder {
        TextReminder(
            personName: name, storedPhone: phone, contactIdentifier: contact, owesYou: owesYou, youOwe: youOwe,
            expense: expense
        )
    }

    /// A Loan or Debt of `cents` with `person`, reminding on `reminderDay`.
    private func remind(_ role: LockedRole, _ cents: Int, with person: Person, on reminderDay: CalendarDay) throws {
        var draft = TransactionDraft(type: .debtLoan, day: day(2026, 5, 27))
        draft.wallet = fixture.checking
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.people = [person]
        draft.reminderDay = reminderDay
        _ = try Transaction.create(draft, in: context)
    }

    private func dollars(_ cents: Int) -> String {
        Money(cents: cents).formatted()
    }

    // MARK: Wording

    @Test func theMessageNamesWhatThePersonOwesYouWithTheAppsMoneyFormatting() {
        let message = text(owesYou: [Money(cents: 130_00)])

        #expect(message.body == "Hi Alex, a reminder that you owe me \(dollars(130_00)).")
    }

    @Test func theMessageNamesWhatYouOweThemWhenItIsOnlyADebt() {
        let message = text("Anna", youOwe: [Money(cents: 50_00)])

        #expect(message.body == "Hi Anna, I owe you \(dollars(50_00)).")
    }

    @Test func theMessageKeepsWhatTheyOweYouApartFromWhatYouOweThem() {
        let message = text(owesYou: [Money(cents: 100_00)], youOwe: [Money(cents: 40_00)])

        #expect(message.body == "Hi Alex, you owe me \(dollars(100_00)), and I owe you \(dollars(40_00)).")
    }

    @Test func everyCurrencyOwedIsNamedOnceWithoutAddingThemUp() {
        let euros = Money(cents: 25_00, currencyCode: "EUR")
        let message = text(owesYou: [euros, Money(cents: 130_00)])

        #expect(message.body.contains(euros.formatted()))
        #expect(message.body.contains(dollars(130_00)))
    }

    @Test func aPersonsRowTextsWhatTheyOweAndWhatYouOweThem() throws {
        let alex = try fixture.person("Alex")
        alex.phone = "555 0100"
        try fixture.dinner(owing: [(alex, 30_00)])
        let entry = try #require(try DebtsAndLoansByPerson(in: context).entry(for: alex))

        let message = TextReminder(entry)

        #expect(message.personName == "Alex")
        #expect(message.storedPhone == "555 0100")
        #expect(message.owesYou == [Money(cents: 30_00)])
        #expect(message.body == "Hi Alex, a reminder that you owe me \(dollars(30_00)).")
    }

    // MARK: From a notification

    @Test func theOwesMeNotificationsActionTextsAboutTheAmountAndTheExpense() throws {
        let alex = try fixture.person("Alex")
        alex.phone = "555 0100"
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(alex, 30_00)])
        dinner.note = "Dinner"
        let reminder = try #require(fixture.owesMe().reminders(from: dinnerDay).first)

        let message = try #require(TextReminder(userInfo: reminder.userInfo))

        #expect(message.personName == "Alex")
        #expect(message.storedPhone == "555 0100")
        #expect(message.body == "Hi Alex, a reminder that you owe me \(dollars(30_00)) for Dinner.")
    }

    @Test func anOpenAmountNotificationNamesTheExpenseAlone() throws {
        let sam = try fixture.person("Sam")
        let dinner = try fixture.dinner(on: dinnerDay, owing: [(sam, nil)])
        dinner.note = "Dinner"
        let reminder = try #require(fixture.owesMe().reminders(from: dinnerDay).first)

        let message = try #require(TextReminder(userInfo: reminder.userInfo))

        #expect(message.body == "Hi Sam, a reminder that you owe me for Dinner.")
    }

    @Test func aLoanNotificationTextsWhatTheyOweAndADebtNotificationWhatYouOwe() throws {
        let today = fixture.today
        let pasha = try fixture.person("Pasha")
        pasha.phone = "555 0111"
        let anna = try fixture.person("Anna")
        try remind(.loan, 40_00, with: pasha, on: today)
        try remind(.debt, 50_00, with: anna, on: today)

        let reminders = try DebtsAndLoans(in: context).reminders(from: today)

        let loan = try #require(reminders.first { $0.withName == "Pasha" })
        let debt = try #require(reminders.first { $0.withName == "Anna" })
        let textLoan = try #require(TextReminder(userInfo: loan.userInfo))
        let textDebt = try #require(TextReminder(userInfo: debt.userInfo))
        #expect(DebtReminder.categoryIdentifier == "grosh.debt")
        #expect(textLoan.storedPhone == "555 0111")
        #expect(textLoan.body == "Hi Pasha, a reminder that you owe me \(dollars(40_00)).")
        #expect(textDebt.storedPhone == nil)
        #expect(textDebt.body == "Hi Anna, I owe you \(dollars(50_00)).")
    }

    @Test func bothReminderSortsOfferTheActionInTheirOwnCategory() {
        let categories = [ExpectedReimbursementReminder.categoryIdentifier, DebtReminder.categoryIdentifier]

        #expect(categories == ["grosh.owes-me", "grosh.debt"])
        #expect(LocalNotificationReminders.textThemAction == "grosh.text-them")
    }

    @Test func thePersonInTheStoreWinsOverWhatTheNotificationWasScheduledWith() throws {
        let alex = try fixture.person("Alex")
        alex.phone = "555 0200"
        alex.contactIdentifier = "c1"
        let info = ["person": "alex", "phone": "555 0100", "amountCents": "3000", "currencyCode": "USD"]

        let message = try #require(TextReminder(userInfo: info, person: alex))

        #expect(message.personName == "Alex")
        #expect(message.storedPhone == "555 0200")
        #expect(message.contactIdentifier == "c1")
    }

    @Test func aNotificationWithoutAPersonHasNoOneToText() {
        #expect(TextReminder(userInfo: [:]) == nil)
        #expect(TextReminder(userInfo: ["person": "  "]) == nil)
    }

    // MARK: Live or stored phone

    @Test func theLivePhoneIsUsedWhenTheContactResolves() async {
        let lookup = RecordingContactLookup([Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200"])])

        let phone = await text(phone: "555 0100", contact: "c1").phone(using: lookup)

        #expect(phone == "555 0200")
    }

    @Test func theStoredPhoneStaysWhileTheContactStillHasIt() async {
        let contact = Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200", "555 0100"])
        let lookup = RecordingContactLookup([contact])

        let phone = await text(phone: "555 0100", contact: "c1").phone(using: lookup)

        #expect(phone == "555 0100")
    }

    @Test func theStoredPhoneIsUsedWhenTheContactDoesNotResolve() async {
        let lookup = RecordingContactLookup([])

        let phone = await text(phone: "555 0100", contact: "gone").phone(using: lookup)

        #expect(phone == "555 0100")
    }

    @Test func theStoredPhoneIsUsedWhenAccessToContactsIsOff() async {
        let book = [Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200"])]
        let lookup = RecordingContactLookup(book, access: .denied)

        let phone = await text(phone: "555 0100", contact: "c1").phone(using: lookup)

        #expect(phone == "555 0100")
    }

    @Test func theStoredPhoneIsUsedWhenTheContactHasNoNumber() async {
        let lookup = RecordingContactLookup([Contact(identifier: "c1", name: "Alex")])

        let phone = await text(phone: "555 0100", contact: "c1").phone(using: lookup)

        #expect(phone == "555 0100")
    }

    @Test func aPersonNotLinkedToAContactUsesTheirStoredPhoneWithoutAskingContacts() async {
        let lookup = RecordingContactLookup([Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200"])])

        let phone = await text(phone: "555 0100").phone(using: lookup)

        #expect(phone == "555 0100")
        #expect(lookup.calls.isEmpty)
    }

    @Test func aLinkedPersonWithNoStoredPhoneStillGetsTheContactsNumber() async {
        let lookup = RecordingContactLookup([Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200"])])

        let phone = await text(contact: "c1").phone(using: lookup)

        #expect(phone == "555 0200")
    }

    @Test func thereIsNoPhoneWhenNeitherHasOne() async {
        let phone = await text(contact: "c1").phone(using: RecordingContactLookup([]))

        #expect(phone == nil)
    }

    // MARK: Compose, or copy and share

    @Test func whenTextingIsAvailableTheComposeSheetOpensWithThePhoneAndTheMessage() async {
        let message = text(phone: "555 0100", owesYou: [Money(cents: 30_00)])

        let delivery = await message.delivery(canSendText: true, using: RecordingContactLookup())

        #expect(delivery == .compose(phone: "555 0100", body: message.body))
    }

    @Test func theComposeSheetGetsTheLivePhoneWhenTheContactResolves() async {
        let lookup = RecordingContactLookup([Contact(identifier: "c1", name: "Alex", phoneNumbers: ["555 0200"])])
        let message = text(phone: "555 0100", contact: "c1", owesYou: [Money(cents: 30_00)])

        let delivery = await message.delivery(canSendText: true, using: lookup)

        #expect(delivery == .compose(phone: "555 0200", body: message.body))
    }

    @Test func whenTextingIsUnavailableTheMessageCanBeCopiedOrSharedInstead() async {
        let lookup = RecordingContactLookup()
        let message = text(phone: "555 0100", contact: "c1", owesYou: [Money(cents: 30_00)])

        let delivery = await message.delivery(canSendText: false, using: lookup)

        #expect(delivery == .copyOrShare(body: message.body))
        #expect(lookup.calls.isEmpty)
    }

    @Test func aPersonWithNoPhoneCanOnlyHaveTheMessageCopiedOrShared() async {
        let message = text(owesYou: [Money(cents: 30_00)])

        let delivery = await message.delivery(canSendText: true, using: RecordingContactLookup())

        #expect(delivery == .copyOrShare(body: message.body))
    }
}
