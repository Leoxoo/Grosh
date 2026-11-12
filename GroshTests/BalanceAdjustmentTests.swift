import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Adjust Balance: typing a wallet's real balance records the difference as one balance adjustment.
@MainActor
@Suite(.namedInTheLog)
struct BalanceAdjustmentTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
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
        try store.record(1_000_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try store.record(-40_00, "Café", on: CalendarDay(year: 2026, month: 10, day: 3))

        try adjust(to: 975_55)

        #expect(walletBalance(checking, asOf: today) == Money(cents: 975_55))
    }

    @Test func adjustingOnAnEarlierDaySetsTheBalanceOnThatDay() throws {
        let fifth = CalendarDay(year: 2026, month: 10, day: 5)
        try store.record(1_000_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try store.record(-40_00, "Café", on: CalendarDay(year: 2026, month: 10, day: 8))

        try adjust(to: 900_00, on: fifth)

        #expect(walletBalance(checking, asOf: fifth) == Money(cents: 900_00))
        #expect(walletBalance(checking, asOf: today) == Money(cents: 860_00))
    }

    // MARK: Where Adjust Balance starts

    @Test func adjustingWhileViewingAWalletStartsTodayInThatWallet() throws {
        try store.record(500_00, "Salary", .income, on: today)
        let savings = context.addWallet("Savings")

        let suggested = try TransactionDefaults.suggestBalanceAdjustment(
            on: today, viewing: savings, balances: WalletBalances(of: [checking, savings], asOf: today), in: context
        )

        #expect(suggested.wallet == savings)
        #expect(suggested.day == today)
    }

    @Test func adjustingFromTheTotalStartsInTheLastUsedWallet() throws {
        let savings = context.addWallet("Savings")
        try store.record(-4_50, "Café", on: today).createdAt = .distantPast
        try store.record(75_00, "Salary", .income, on: today, in: savings)

        let suggested = try TransactionDefaults.suggestBalanceAdjustment(
            on: today, balances: WalletBalances(of: [checking, savings], asOf: today), in: context
        )

        #expect(suggested.wallet == savings)
    }

    // MARK: The real balance starts from the recorded one

    @Test func theRealBalanceStartsAtTheRecordedBalanceSoThereIsNothingToAdjust() throws {
        try store.record(500_00, "Salary", .income, on: today)

        let draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        #expect(draft.realBalance == Money(cents: 500_00))
        #expect(!draft.canSave)
    }

    @Test func changingTheDayBeforeTypingStartsAgainFromThatDaysRecordedBalance() throws {
        try store.record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        draft.day = today.adding(days: -1)
        draft.readRecordedBalance()

        #expect(draft.realBalance == Money(cents: 0))
        #expect(!draft.canSave)
    }

    @Test func changingTheDayKeepsARealBalanceAlreadyTyped() throws {
        try store.record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.entry.press(.digit(7))

        draft.day = today.adding(days: -1)
        draft.readRecordedBalance()

        #expect(draft.realBalance == Money(cents: 7_00))
        #expect(draft.difference == Money(cents: 7_00))
    }

    @Test func changingTheWalletStartsAgainFromThatWalletsRecordedBalance() throws {
        try store.record(500_00, "Salary", .income, on: today)
        let savings = context.addWallet("Savings")
        try store.record(75_00, "Salary", .income, on: today, in: savings)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 450_00)

        draft.wallet = savings
        draft.readRecordedBalance()

        #expect(draft.realBalance == Money(cents: 75_00))
        #expect(!draft.canSave)
    }

    @Test func untilTheNewWalletsBalanceIsReadThereIsNothingToAdjust() throws {
        try store.record(500_00, "Salary", .income, on: today)
        let savings = context.addWallet("Savings")
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 450_00)

        draft.wallet = savings
        draft.realBalance = Money(cents: 10_00)

        #expect(draft.recordedBalance == nil)
        #expect(draft.difference == nil)
        #expect(!draft.canSave)
    }

    @Test func theFirstDigitTypedReplacesTheRecordedBalance() throws {
        try store.record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        draft.entry.press(.digit(4))
        draft.entry.press(.digit(2))

        #expect(draft.realBalance == Money(cents: 42_00))
        #expect(draft.difference == Money(cents: -458_00))
    }

    @Test func aRealBalanceTheKeypadCantWorkOutCantBeSaved() throws {
        try store.record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        for key: KeypadKey in [.digit(4), .operation(.divide), .digit(0), .equals] {
            draft.entry.press(key)
        }

        #expect(draft.realBalance == nil)
        #expect(!draft.canSave)
    }

    @Test func aRealBalanceCanBeTypedBelowZeroWithALeadingMinus() throws {
        try store.record(500_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)

        for key: KeypadKey in [.allClear, .operation(.subtract), .digit(4), .digit(2)] {
            draft.entry.press(key)
        }

        #expect(draft.realBalance == Money(cents: -42_00))
        #expect(draft.difference == Money(cents: -542_00))
    }

    // MARK: The reason

    @Test func aRealBalanceAboveTheRecordedOneIsOtherIncome() throws {
        try store.record(100_00, "Salary", .income, on: today)

        let adjustment = try adjust(to: 115_55)

        #expect(adjustment.amount == Money(cents: 15_55))
        #expect(adjustment.category == (try context.lockedCategory(.otherIncome)))
    }

    @Test func aRealBalanceBelowTheRecordedOneIsOtherExpense() throws {
        try store.record(100_00, "Salary", .income, on: today)

        let adjustment = try adjust(to: 84_45)

        #expect(adjustment.amount == Money(cents: -15_55))
        #expect(adjustment.category == (try context.lockedCategory(.otherExpense)))
    }

    @Test func theReasonCanBeAnyCategoryOfTheMatchingType() throws {
        try store.record(100_00, "Salary", .income, on: today)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 101_20)
        draft.category = try store.category("Collect Interest", .income)

        let adjustment = try Transaction.adjustBalance(draft, in: context)

        #expect(adjustment.category == (try store.category("Collect Interest", .income)))
    }

    @Test func aReasonOfTheOtherTypeGivesWayToTheDefaultUntilTheSignComesBack() throws {
        try store.record(100_00, "Salary", .income, on: today)
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
        #expect(walletBalance(checking, asOf: today) == Money(cents: -74_91))
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
        let coffee = try store.record(-4_50, "Café", on: today)

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
        try store.record(100_00, "Salary", .income, on: CalendarDay(year: 2026, month: 10, day: 1))
        try store.record(-4_50, "Café", on: today)

        let adjustment = try adjust(to: 80_00)

        #expect(adjustment.balanceChange?.recorded == Money(cents: 95_50))
        #expect(adjustment.balanceChange?.actual == Money(cents: 80_00))
    }

    @Test func whatIsEnteredLaterTheSameDayDoesntChangeRecordedOrActual() throws {
        try store.record(100_00, "Salary", .income, on: today)
        let adjustment = try adjust(to: 80_00)

        let lunch = try store.record(-12_00, "Restaurants", on: today)
        lunch.createdAt = adjustment.createdAt.addingTimeInterval(60)

        #expect(adjustment.balanceChange?.recorded == Money(cents: 100_00))
        #expect(adjustment.balanceChange?.actual == Money(cents: 80_00))
    }

    @Test func onlyABalanceAdjustmentHasABalanceChange() throws {
        let coffee = try store.record(-4_50, "Café", on: today)

        #expect(coffee.balanceChange == nil)
    }

    // MARK: Nothing to adjust

    @Test func aRealBalanceEqualToTheRecordedOneHasNothingToAdjust() throws {
        try store.record(100_00, "Salary", .income, on: today)
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

    @Test func aNegativeAdjustmentInAWalletWithCardsIsSavedWithoutACard() throws {
        try context.addCard(paidFrom: checking)

        let adjustment = try adjust(to: -15_55)

        #expect(adjustment.card == nil)
        #expect(walletBalance(checking, asOf: today) == Money(cents: -15_55))
    }

    @Test func editingANegativeAdjustmentInAWalletWithCardsStillNeedsNoCard() throws {
        try context.addCard(paidFrom: checking)
        let adjustment = try adjust(to: -15_55)

        var draft = TransactionDraft(editing: adjustment)
        draft.amount = Money(cents: 20_00)

        #expect(!draft.requiresCard)
        try adjustment.update(with: draft)
        #expect(adjustment.amount == Money(cents: -20_00))
        #expect(adjustment.isBalanceAdjustment)
    }
}
