import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The rules the editors' drafts keep themselves, so no sheet works them out: a Recurring transaction's name, Kind,
/// total and past occurrences, + Owes me's typed amount and who is offered it, a new wallet's Starting balance, a new
/// category, the Split remainder, and the small rules lists and rows read (Recently Deleted's ending soon, a Loan's
/// title, what the Home bell lists, the Month graph comparison).
@MainActor
@Suite(.namedInTheLog)
struct DraftRulesTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var today: CalendarDay { fixture.today }

    init() throws {
        fixture = try ExpectationFixture()
    }

    // MARK: Recurring transaction

    @Test func aNewRecurringTransactionIsNamedAfterItsCategoryAndTakesItsKind() {
        let streaming = context.addCategory("Streaming")
        streaming.ownKind = .subscription
        let rent = context.addCategory("Rent")
        var draft = RecurringDraft(startDay: today)

        draft.pickedCategory = streaming
        #expect(draft.name == "Streaming")
        #expect(draft.kind == .subscription)

        draft.pickedCategory = rent
        #expect(draft.name == "Rent")
        #expect(draft.kind == .regular)

        draft.name = "Flat"
        draft.pickedCategory = streaming
        #expect(draft.name == "Flat")
    }

    @Test func switchingTypeDropsTheCategoryAndTheNameThatFollowedIt() {
        var draft = RecurringDraft(startDay: today)
        draft.pickedCategory = context.addCategory("Rent")

        draft.type = .income

        #expect(draft.category == nil)
        #expect(draft.name.isEmpty)
    }

    @Test func anEditedRecurringTransactionKeepsItsKindWhenTheCategoryChanges() throws {
        let streaming = context.addCategory("Streaming")
        streaming.ownKind = .subscription
        var draft = RecurringDraft(startDay: today)
        draft.name = "Gym"
        draft.entry = AmountEntry(cents: 30_00)
        draft.wallet = fixture.checking
        draft.pickedCategory = context.addCategory("Sport")
        let saved = try RecurringTransaction.create(draft, today: today, in: context)

        var edited = RecurringDraft(editing: saved)
        edited.pickedCategory = streaming

        #expect(!edited.isNew)
        #expect(edited.kind == .regular)
    }

    @Test func pastOccurrencesAreOfferedForANewScheduleOrAMovedStart() throws {
        var draft = RecurringDraft(startDay: today)
        draft.name = "Gym"
        draft.entry = AmountEntry(cents: 30_00)
        draft.wallet = fixture.checking
        draft.pickedCategory = context.addCategory("Sport")
        #expect(draft.offersPastOccurrences)
        let saved = try RecurringTransaction.create(draft, today: today, in: context)

        var edited = RecurringDraft(editing: saved)
        #expect(!edited.offersPastOccurrences)
        edited.startDay = today.adding(days: -30)
        #expect(edited.offersPastOccurrences)
        #expect(RecurringDraft(duplicating: saved, on: today).offersPastOccurrences)
    }

    @Test func aTotalOfZeroIsNoTotalAndOneThatCantBeWorkedOutIsRefused() {
        var draft = RecurringDraft(startDay: today)
        draft.name = "Laptop"
        draft.entry = AmountEntry(cents: 100_00)
        draft.wallet = fixture.checking
        draft.pickedCategory = context.addCategory("Gadgets")

        draft.totalEntry = AmountEntry(showing: 0)
        #expect(draft.total == nil)
        #expect(draft.canSave)

        draft.totalEntry = AmountEntry(cents: 1_200_00)
        #expect(draft.total == Money(cents: 1_200_00))

        draft.totalEntry.press(.operation(.divide))
        draft.totalEntry.press(.digit(0))
        draft.totalEntry.press(.equals)
        #expect(draft.check.problem as? RecurringRuleError == .invalidTotal)
    }

    // MARK: + Owes me

    @Test func aTypedOwesMeAmountIsOpenWhenBlankAndZeroWhenItIsNoAmount() throws {
        var owes = OwesMeDraft(person: try fixture.person("Ann"), expenseDay: today)

        owes.entry = AmountEntry(cents: 12_00)
        #expect(owes.expectedCents == 12_00)

        owes.entry = AmountEntry()
        #expect(owes.expectedCents == nil)

        owes.entry = AmountEntry(cents: 5_00)
        owes.entry.press(.operation(.divide))
        owes.entry.press(.digit(0))
        owes.entry.press(.equals)
        #expect(owes.expectedCents == 0)
    }

    @Test func owesMeIsOfferedForThoseInWithWhoDontOweYetOnAnExpense() throws {
        let ann = try fixture.person("Ann")
        let bob = try fixture.person("Bob")
        var draft = TransactionDraft(type: .expense, day: today)
        draft.wallet = fixture.checking
        draft.category = try fixture.store.category("Restaurants")
        draft.people = [ann, bob]
        draft.addOwes(ann)

        #expect(draft.peopleOfferedOwesMe.map(\.name) == ["Bob"])

        draft.type = .income
        #expect(draft.peopleOfferedOwesMe.isEmpty)
    }

    // MARK: Wallet and category

    @Test func aNewWalletNeedsAStartingBalanceTheKeypadCanWorkOut() throws {
        var draft = WalletDraft(currencyCode: "EUR")
        draft.name = "Savings"
        #expect(draft.startingBalance == Money(cents: 0, currencyCode: "EUR"))

        draft.startingBalanceEntry = AmountEntry(cents: -50_00, kind: .balance)
        let wallet = try Wallet.create(draft, startingOn: today, in: context)
        #expect(wallet.transactions?.first?.amountCents == -50_00)

        draft.startingBalanceEntry.press(.operation(.divide))
        draft.startingBalanceEntry.press(.digit(0))
        draft.startingBalanceEntry.press(.equals)
        #expect(throws: WalletRuleError.invalidStartingBalance) { try draft.validate() }
    }

    @Test func aNewCategoryStartsAsATagOnBlueAndNeedsAName() {
        var draft = CategoryDraft.new(.income)
        #expect(draft.type == .income)
        #expect(draft.symbolName == "tag.fill")
        #expect(draft.color == .blue)
        #expect(draft.check.problem as? CategoryRuleError == .nameRequired)
        #expect(draft.shownProblem == nil)

        draft.name = "  Tips "
        #expect(draft.canSave)
        #expect(draft.trimmedName == "Tips")
    }

    // MARK: Split

    @Test func theTransactionBeingSplitKeepsWhatIsLeftEvenBelowZero() throws {
        var split = SplitDraft(splitting: try fixture.dinner(60_00))
        var part = split.newPart()
        #expect(part.entry.isEmpty)
        part.entry = AmountEntry(cents: 80_00)

        split.addPart(part)
        #expect(split.original.amount.cents == -20_00)
        #expect(split.leavesNothingOnOriginal)

        split.removePart(at: 0)
        #expect(split.original.amount.cents == 60_00)
    }

    // MARK: Lists and rows

    @Test func anItemInRecentlyDeletedEndsSoonWithThreeDaysLeftOrFewer() {
        #expect(RecentlyDeleted.daysLeft(since: nil, now: .now) == RecentlyDeleted.keptDays)
        #expect(RecentlyDeleted.isEndingSoon(daysLeft: 3))
        #expect(!RecentlyDeleted.isEndingSoon(daysLeft: 4))
    }

    @Test func aLoanIsTitledByWhoItIsWithOrElseItsCategory() throws {
        let original = try context.recordLoanOrDebt(
            .loan, 100_00, with: fixture.person("Pasha"), on: today, in: fixture.checking
        )
        let loan = try #require(try LoanOrDebt(original))
        #expect(loan.title == "Pasha")

        original.withName = ""
        #expect(loan.title == original.categoryName)
    }

    @Test func theBellListsWhatIsDue() throws {
        try fixture.dinner(owing: [(person: try fixture.person("Ann"), cents: 20_00)])
        let expectations = try context.fetch(ExpectedReimbursements.records)

        let before = DueReminders(transactions: [], expectations: expectations, estimates: [], on: day(2026, 10, 9))
        let after = DueReminders(transactions: [], expectations: expectations, estimates: [], on: day(2026, 10, 10))

        #expect(before.isEmpty)
        #expect(after.count == 1)
        #expect(after.expectations.map(\.personName) == ["Ann"])
    }

    @Test func theSwitchPicksLastYearOrTheAverage() {
        #expect(MonthGraphComparison(comparesWithLastYear: true) == .lastYear)
        #expect(MonthGraphComparison(comparesWithLastYear: false) == .average)
    }
}
