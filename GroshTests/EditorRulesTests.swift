import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The rules the Keypad sheets share: the draft with the typed amount, which way the amount is tinted, why Save is off
/// as the footer says it, and the small rules the Split, Card, Record payment, Reimbursement and merge sheets read.
@MainActor
@Suite(.namedInTheLog)
struct EditorRulesTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }

    init() throws {
        fixture = try ExpectationFixture()
    }

    // MARK: The typed amount

    @Test func theDraftsAmountIsWhatItsKeypadComesToInItsWalletsCurrency() {
        let euros = context.addWallet("Euros")
        euros.currencyCode = "EUR"
        var draft = TransferDraft(day: day(2026, 10, 3))
        draft.from = euros
        #expect(draft.amount == Money(cents: 0, currencyCode: "EUR"))

        draft.entry.press(.digit(1))
        draft.entry.press(.digit(2))
        draft.entry.press(.operation(.divide))
        draft.entry.press(.digit(4))
        #expect(draft.amount == Money(cents: 3_00, currencyCode: "EUR"))

        draft.entry = AmountEntry()
        draft.entry.press(.digit(5))
        draft.entry.press(.operation(.divide))
        draft.entry.press(.digit(0))
        draft.entry.press(.equals)
        #expect(draft.amount == Money(cents: 0, currencyCode: "EUR"))
    }

    @Test func eachDraftStartsItsKeypadByItsOwnRule() throws {
        let restaurants = try fixture.store.category("Restaurants")
        let dinner = context.record(-42_00, on: day(2026, 10, 1), in: fixture.checking, under: restaurants)
        try context.save()

        #expect(TransferDraft(day: day(2026, 10, 3)).entry.isEmpty)
        #expect(ReimbursementDraft(payingBack: dinner, on: day(2026, 10, 3)).entry.isEmpty)
        #expect(TransactionDraft(editing: dinner).entry == AmountEntry(cents: 42_00))
        #expect(StartingBalanceDraft(editing: dinner).entry == AmountEntry(cents: -42_00, kind: .balance))
    }

    @Test func aStartingBalanceSavesAnyAmountTheKeypadCanWorkOutZeroIncluded() throws {
        var draft = StartingBalanceDraft(editing: try fixture.dinner())
        draft.entry = AmountEntry()
        #expect(draft.canSave)

        draft.entry.press(.digit(5))
        draft.entry.press(.operation(.divide))
        draft.entry.press(.digit(0))
        draft.entry.press(.equals)
        #expect(!draft.canSave)
    }

    @Test func anAmountIsTintedTheWayItsCategoryMovesTheWallet() throws {
        let restaurants = try fixture.store.category("Restaurants")
        #expect(MoneyDirection(category: restaurants) == .moneyOut)
        #expect(MoneyDirection(category: nil) == .neither)
        #expect(MoneyDirection(sign: 5) == .moneyIn)
        #expect(Money(cents: 0).direction == .neither)
        #expect(LoanOrDebtKind.loan.paymentDirection == .moneyIn)
        #expect(LoanOrDebtKind.debt.paymentDirection == .moneyOut)
    }

    // MARK: Why Save is off

    @Test func aFooterLeavesOutAFieldStillEmptyButSaysAnyOtherReason() {
        var draft = TransferDraft(day: day(2026, 10, 3))
        #expect(draft.shownProblem as? TransferRuleError == .missingSourceWallet)

        draft.from = fixture.checking
        draft.to = fixture.cash
        #expect(!draft.canSave)
        #expect(draft.shownProblem == nil)

        draft.to = fixture.checking
        draft.amount = Money(cents: 5_00)
        #expect(draft.shownProblem as? TransferRuleError == .sameWallet)

        draft.to = fixture.cash
        #expect(draft.canSave)
        #expect(draft.check.problem == nil)
    }

    @Test func anExpenseInAWalletWithACardSaysItNeedsTheCardOnceItsAmountAndCategoryAreIn() throws {
        try Card.create(CardDraft(name: "Visa", kind: .credit, payingWallet: fixture.checking), in: context)
        var draft = TransactionDraft(type: .expense, day: day(2026, 10, 3))
        draft.wallet = fixture.checking
        #expect(draft.shownProblem == nil)

        draft.amount = Money(cents: 10_00)
        draft.category = try fixture.store.category("Restaurants")
        #expect(draft.shownProblem as? TransactionRuleError == .missingCard)
    }

    // MARK: Split

    @Test func aPartCanTakeWhatIsLeftOnTheTransactionBeingSplitPlusWhatItTakesAlready() throws {
        let dinner = try fixture.dinner(60_00)
        var split = SplitDraft(splitting: dinner)
        var part = split.newPart()
        part.amount = Money(cents: 20_00)
        split.addPart(part)

        #expect(split.capacity(of: nil)?.cents == 40_00)
        #expect(split.capacity(of: .part(0))?.cents == 60_00)
        #expect(split.capacity(of: .original) == nil)
        #expect(part.leftOver(from: Money(cents: 60_00)).cents == 40_00)
        #expect(split.partType == .expense)
        #expect(!split.leavesNothingOnOriginal)
        #expect(part.isComplete)

        part.amount = Money(cents: 0)
        #expect(!part.isComplete)
    }

    // MARK: Card

    @Test func onlyACreditCardKeepsTheStatementDateTheFormRemembers() {
        var draft = CardDraft.new
        #expect(draft.offersStatementDate)
        #expect(draft.withStatementDay(15).statementDay == 15)

        draft.kind = .debit
        #expect(!draft.offersStatementDate)
        #expect(draft.withStatementDay(15).statementDay == nil)
    }

    @Test func theLastFourDigitsKeepOnlyTheFirstFourDigitsTyped() {
        var draft = CardDraft.new
        draft.setLastFourDigits(typed: "12a3 456")
        #expect(draft.lastFourDigits == "1234")
    }

    @Test func aNewCardStartsPaidFromTheFirstWalletAndKeepsOneAlreadyChosen() {
        var draft = CardDraft.new
        draft.startPaying(from: [fixture.cash, fixture.checking])
        #expect(draft.payingWallet === fixture.cash)

        draft.startPaying(from: [fixture.checking])
        #expect(draft.payingWallet === fixture.cash)
    }

    // MARK: Net income bars

    @Test func theLargerSideFillsItsBarAndTheOtherIsInProportion() {
        let totals = PeriodTotals(income: Money(cents: 400_00), spent: Money(cents: 100_00))
        #expect(totals.barFraction(of: .income) == 1)
        #expect(totals.barFraction(of: .spent) == 0.25)

        let refunded = PeriodTotals(income: Money(cents: 0), spent: Money(cents: -10_00))
        #expect(refunded.barFraction(of: .spent) == 0)
        #expect(refunded.barFraction(of: .income) == 0)
    }

    // MARK: Paid back

    @Test func moneyPaidBackIntoTheExpensesWalletIsKeptOnItAndIntoAnotherIsATransactionThere() throws {
        let dinner = try fixture.dinner(60_00)
        try dinner.recordPayback(
            ReimbursementDraft(amount: Money(cents: 10_00), day: day(2026, 10, 5)), into: fixture.checking, in: context
        )
        try dinner.recordPayback(
            ReimbursementDraft(amount: Money(cents: 5_00), day: day(2026, 10, 6)), into: fixture.cash, in: context
        )

        #expect(dinner.orderedReimbursements.map(\.amountCents) == [10_00])
        #expect(dinner.paybacksElsewhere.map(\.wallet) == [fixture.cash])
    }

    @Test func aRowShowsTheNetOnlyOnceSomethingWasPaidBack() throws {
        let dinner = try fixture.dinner(60_00)
        #expect(dinner.paidBackNet(.net) == nil)
        #expect(dinner.paidBackSummary(.net).isEmpty)

        try dinner.recordPayback(
            ReimbursementDraft(amount: Money(cents: 20_00), day: day(2026, 10, 5)), into: fixture.checking, in: context
        )
        #expect(dinner.paidBackNet(.net)?.cents == -40_00)
        #expect(dinner.paidBackSummary(.net, locale: Locale(identifier: "en_US")) == "+20")
    }

    @Test func aPaymentAboveALoanComesInAndAboveADebtGoesOut() throws {
        let loan = try fixture.store.category("Loan", .debtLoan)
        var draft = TransactionDraft(type: .debtLoan, day: day(2026, 10, 3))
        draft.wallet = fixture.checking
        draft.amount = Money(cents: 50_00)
        draft.category = loan
        draft.people = [try fixture.person("Alex")]
        let lent = try Transaction.create(draft, in: context)

        var payment = try DebtPaymentDraft(settling: lent, on: day(2026, 10, 9), in: context)
        payment.amount = Money(cents: 70_00)
        #expect(payment.signedOverpaid.cents == 20_00)
    }

    // MARK: Merging and With

    @Test func theMergeFooterSaysWhereTheTransactionsAndSubcategoriesGo() {
        let text = MergeConsequences.text(
            sourceName: "Food", transactionCount: 3, subcategoryCount: 2, targetName: "Groceries", unchosen: "the one you pick"
        )
        #expect(text == "Its 3 transactions move to “Groceries” and its 2 subcategories move under it. Then “Food” is removed.")

        let one = MergeConsequences.text(sourceName: "Visa", transactionCount: 1, targetName: nil, unchosen: "the Card you pick")
        #expect(one == "Its transaction moves to the Card you pick. Then “Visa” is removed.")
    }

    @Test func withNamesItsPeopleByNameJoinedAsTheTransactionKeepsThem() throws {
        let zoe = try fixture.person("Zoe")
        let alex = try fixture.person("Alex")
        #expect(Transaction.withName(of: [zoe, alex]) == "Alex; Zoe")
    }

    @Test func aCategoryWithTransactionsIsCountedInTheStore() throws {
        let catalog = CategoryCatalog(context: context)
        let restaurants = try fixture.store.category("Restaurants")
        #expect(!catalog.hasTransactions(restaurants))

        try fixture.dinner(60_00)
        #expect(catalog.hasTransactions(restaurants))
    }
}
