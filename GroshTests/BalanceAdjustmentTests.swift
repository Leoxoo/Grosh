import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Adjust Balance: typing a wallet's real balance records the difference as one balance adjustment.
@MainActor
struct BalanceAdjustmentTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.wallet }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// Records `cents` (signed) in `wallet` (Checking unless given) on `day`, filed under `categoryName`.
    @discardableResult
    private func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, in wallet: Wallet? = nil, on day: CalendarDay
    ) throws -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = wallet ?? checking
        transaction.category = try store.category(categoryName, type)
        return transaction
    }

    /// A second wallet, after Checking.
    private func addSavings() -> Wallet {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        return savings
    }

    /// Adjusts Checking to a real balance of `cents` on `day`.
    @discardableResult
    private func adjust(to cents: Int, on day: CalendarDay? = nil) throws -> Transaction {
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: day ?? today, in: context)
        draft.realBalance = Money(cents: cents)
        return try Transaction.adjustBalance(draft, in: context)
    }

    // MARK: The balance becomes what was typed

    @Test func afterAdjustingTheWalletBalanceEqualsTheTypedAmount() throws {
        try record(1_000_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try record(-40_00, "Café", on: CalendarDay(year: 2026, month: 10, day: 3))

        try adjust(to: 975_55)

        #expect(checking.balance(asOf: today) == Money(cents: 975_55))
    }

    @Test func adjustingOnAnEarlierDaySetsTheBalanceOnThatDay() throws {
        let fifth = CalendarDay(year: 2026, month: 10, day: 5)
        try record(1_000_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try record(-40_00, "Café", on: CalendarDay(year: 2026, month: 10, day: 8))

        try adjust(to: 900_00, on: fifth)

        #expect(checking.balance(asOf: fifth) == Money(cents: 900_00))
        #expect(checking.balance(asOf: today) == Money(cents: 860_00))
    }

    // MARK: Where Adjust Balance starts

    @Test func adjustingWhileViewingAWalletStartsTodayInThatWallet() throws {
        try record(500_00, "Salary", .income, on: today)
        let savings = addSavings()

        let suggested = try TransactionDefaults.suggestBalanceAdjustment(on: today, viewing: savings, in: context)

        #expect(suggested.wallet == savings)
        #expect(suggested.day == today)
    }

    @Test func adjustingFromTheTotalStartsInTheLastUsedWallet() throws {
        let savings = addSavings()
        try record(-4_50, "Café", on: today).createdAt = .distantPast
        try record(75_00, "Salary", .income, in: savings, on: today)

        let suggested = try TransactionDefaults.suggestBalanceAdjustment(on: today, in: context)

        #expect(suggested.wallet == savings)
    }

    // MARK: The real balance starts from the recorded one

    @Test func theRealBalanceStartsAtTheRecordedBalanceSoThereIsNothingToAdjust() throws {
        try record(500_00, "Salary", .income, on: today)

        let draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        #expect(draft.realBalance == Money(cents: 500_00))
        #expect(!draft.canSave)
    }

    @Test func changingTheDayBeforeTypingStartsAgainFromThatDaysRecordedBalance() throws {
        try record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        draft.day = today.adding(days: -1)

        #expect(draft.realBalance == Money(cents: 0))
        #expect(!draft.canSave)
    }

    @Test func changingTheDayKeepsARealBalanceAlreadyTyped() throws {
        try record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalanceEntry.press(.digit(7))

        draft.day = today.adding(days: -1)

        #expect(draft.realBalance == Money(cents: 7))
        #expect(draft.difference == Money(cents: 7))
    }

    @Test func changingTheWalletStartsAgainFromThatWalletsRecordedBalance() throws {
        try record(500_00, "Salary", .income, on: today)
        let savings = addSavings()
        try record(75_00, "Salary", .income, in: savings, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 450_00)

        draft.wallet = savings

        #expect(draft.realBalance == Money(cents: 75_00))
        #expect(!draft.canSave)
    }

    @Test func theFirstDigitTypedReplacesTheRecordedBalance() throws {
        try record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        draft.realBalanceEntry.press(.digit(4))
        draft.realBalanceEntry.press(.digit(2))

        #expect(draft.realBalance == Money(cents: 42))
        #expect(draft.difference == Money(cents: -499_58))
    }

    @Test func aRealBalanceTheKeypadCantWorkOutCantBeSaved() throws {
        try record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        for key: KeypadKey in [.digit(4), .operation(.divide), .digit(0), .equals] {
            draft.realBalanceEntry.press(key)
        }

        #expect(draft.realBalance == nil)
        #expect(!draft.canSave)
    }

    // MARK: The reason

    @Test func aRealBalanceAboveTheRecordedOneIsOtherIncome() throws {
        try record(100_00, "Salary", .income, on: today)

        let adjustment = try adjust(to: 115_55)

        #expect(adjustment.amount == Money(cents: 15_55))
        #expect(adjustment.category == (try context.lockedCategory(.otherIncome)))
    }

    @Test func aRealBalanceBelowTheRecordedOneIsOtherExpense() throws {
        try record(100_00, "Salary", .income, on: today)

        let adjustment = try adjust(to: 84_45)

        #expect(adjustment.amount == Money(cents: -15_55))
        #expect(adjustment.category == (try context.lockedCategory(.otherExpense)))
    }

    @Test func theReasonCanBeAnyCategoryOfTheMatchingType() throws {
        try record(100_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 101_20)
        draft.category = try store.category("Collect Interest", .income)

        let adjustment = try Transaction.adjustBalance(draft, in: context)

        #expect(adjustment.category == (try store.category("Collect Interest", .income)))
    }

    @Test func aReasonOfTheOtherTypeGivesWayToTheDefaultUntilTheSignComesBack() throws {
        try record(100_00, "Salary", .income, on: today)
        let interest = try store.category("Collect Interest", .income)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 101_20)
        draft.category = interest

        draft.realBalance = Money(cents: 98_00)
        #expect(draft.category == (try context.lockedCategory(.otherExpense)))

        draft.realBalance = Money(cents: 102_00)
        #expect(draft.category == interest)
    }

    @Test func theAdjustmentKeepsItsNoteAndExcludeFromReport() throws {
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 15_55)
        draft.note = "  Interest for September\n"
        draft.isExcludedFromReport = true

        let adjustment = try Transaction.adjustBalance(draft, in: context)

        #expect(adjustment.note == "Interest for September")
        #expect(adjustment.isExcludedFromReport)
    }

    // MARK: Recording a known difference

    /// What the importer does with a transfer row that has no partner.
    @Test func aKnownDifferenceIsRecordedAsABalanceAdjustmentThatKeepsItsExcludedFlag() throws {
        let adjustment = try Transaction.recordBalanceAdjustment(
            Money(cents: -74_91), in: checking, on: today, note: "to old savings", isExcludedFromReport: true, in: context
        )

        #expect(adjustment.isBalanceAdjustment)
        #expect(adjustment.isExcludedFromReport)
        #expect(adjustment.category == (try context.lockedCategory(.otherExpense)))
        #expect(adjustment.note == "to old savings")
        #expect(checking.balance(asOf: today) == Money(cents: -74_91))
    }

    @Test func aKnownDifferenceCountsInReportsUnlessExcluded() throws {
        let adjustment = try Transaction.recordBalanceAdjustment(Money(cents: 20_00), in: checking, on: today, in: context)

        #expect(!adjustment.isExcludedFromReport)
        #expect(adjustment.category == (try context.lockedCategory(.otherIncome)))
    }

    @Test func aReasonOfTheOtherTypeIsRefused() throws {
        let cafe = try store.category("Café")

        #expect(throws: BalanceAdjustmentRuleError.reasonDoesNotMatchDifference) {
            try Transaction.recordBalanceAdjustment(Money(cents: 20_00), in: checking, on: today, reason: cafe, in: context)
        }
        #expect(checking.transactions?.isEmpty == true)
    }

    @Test func anAdjustmentIsEditedInTheAddSheetButNeverDuplicated() throws {
        let adjustment = try adjust(to: 15_55)

        #expect(adjustment.editFlow == .addSheet)
        #expect(!adjustment.canBeDuplicated)
    }

    // MARK: Editing keeps it an adjustment

    @Test func editingAnAdjustmentOffersOnlyExpenseAndIncome() throws {
        let adjustment = try adjust(to: 15_55)
        let coffee = try record(-4_50, "Café", on: today)

        #expect(TransactionDraft(editing: adjustment).types == [.expense, .income])
        #expect(TransactionDraft(editing: coffee).types == [.expense, .income, .debtLoan])
    }

    @Test func anAdjustmentCantBeEditedIntoALoanOrDebt() throws {
        let adjustment = try adjust(to: 15_55)
        var draft = TransactionDraft(editing: adjustment)
        draft.type = .debtLoan
        draft.category = try context.lockedCategory(.loan)

        #expect(!draft.canSave)
        #expect(throws: BalanceAdjustmentRuleError.reasonDoesNotMatchDifference) { try adjustment.update(with: draft) }
        #expect(adjustment.category == (try context.lockedCategory(.otherIncome)))
        #expect(adjustment.amount == Money(cents: 15_55))
    }

    @Test func anAdjustmentEditedFromIncomeToExpenseStaysAnAdjustmentWithTheMatchingSign() throws {
        let adjustment = try adjust(to: 15_55)
        var draft = TransactionDraft(editing: adjustment)
        draft.type = .expense
        draft.category = try context.lockedCategory(.otherExpense)

        try adjustment.update(with: draft)

        #expect(adjustment.isBalanceAdjustment)
        #expect(adjustment.amount == Money(cents: -15_55))
    }

    // MARK: Recorded → actual

    @Test func theDetailShowsTheRecordedBalanceAndTheActualOneTyped() throws {
        try record(100_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try record(-4_50, "Café", on: today)

        let adjustment = try adjust(to: 80_00)

        #expect(adjustment.balanceChange?.recorded == Money(cents: 95_50))
        #expect(adjustment.balanceChange?.actual == Money(cents: 80_00))
    }

    @Test func whatIsEnteredLaterTheSameDayDoesntChangeRecordedOrActual() throws {
        try record(100_00, "Salary", .income, on: today)
        let adjustment = try adjust(to: 80_00)

        let lunch = try record(-12_00, "Restaurants", on: today)
        lunch.createdAt = adjustment.createdAt.addingTimeInterval(60)

        #expect(adjustment.balanceChange?.recorded == Money(cents: 100_00))
        #expect(adjustment.balanceChange?.actual == Money(cents: 80_00))
    }

    @Test func onlyABalanceAdjustmentHasABalanceChange() throws {
        let coffee = try record(-4_50, "Café", on: today)

        #expect(coffee.balanceChange == nil)
    }

    // MARK: Nothing to adjust

    @Test func aRealBalanceEqualToTheRecordedOneHasNothingToAdjust() throws {
        try record(100_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 100_00)

        #expect(!draft.canSave)
        #expect(throws: BalanceAdjustmentRuleError.nothingToAdjust) { try Transaction.adjustBalance(draft, in: context) }
        #expect(checking.transactions?.count == 1)
    }

    @Test func adjustingNeedsAWallet() throws {
        var draft = try BalanceAdjustmentDraft(wallet: nil, day: today, in: context)
        draft.realBalance = Money(cents: 100_00)

        #expect(!draft.canSave)
        #expect(throws: TransactionRuleError.missingWallet) { try Transaction.adjustBalance(draft, in: context) }
    }

    // MARK: Reports and Cards

    @Test func anAdjustmentIsRecordedAsABalanceAdjustmentThatCountsInReports() throws {
        let adjustment = try adjust(to: 15_55)

        #expect(adjustment.isBalanceAdjustment)
        #expect(!adjustment.isExcludedFromReport)
    }

    @discardableResult
    private func addCard() throws -> Card {
        try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
    }

    @Test func aNegativeAdjustmentInAWalletWithCardsIsSavedWithoutACard() throws {
        try addCard()

        let adjustment = try adjust(to: -15_55)

        #expect(adjustment.card == nil)
        #expect(checking.balance(asOf: today) == Money(cents: -15_55))
    }

    @Test func editingANegativeAdjustmentInAWalletWithCardsStillNeedsNoCard() throws {
        try addCard()
        let adjustment = try adjust(to: -15_55)

        var draft = TransactionDraft(editing: adjustment)
        draft.amount = Money(cents: 20_00)

        #expect(!draft.requiresCard)
        try adjustment.update(with: draft)
        #expect(adjustment.amount == Money(cents: -20_00))
        #expect(adjustment.isBalanceAdjustment)
    }
}
