import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Split: dividing an Expense or Income into linked parts that each take their own amount, category, day, note, With
/// and Event, and Undo split, which merges them back.
@MainActor
struct SplitTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.wallet }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        store = try CategoryFixture()
    }

    /// An Expense (unless `type` says Income) of `cents` under `categoryName`, dated today in Checking, saved through
    /// the Add sheet's draft.
    @discardableResult
    private func record(
        _ cents: Int, _ categoryName: String = "Café", _ type: CategoryType = .expense, card: Card? = nil
    ) throws -> Transaction {
        var draft = TransactionDraft(type: type, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try store.category(categoryName, type)
        draft.card = card
        return try Transaction.create(draft, in: context)
    }

    /// Splits `transaction`, adding a part for each of `cents`, filed under `categoryName` when one is given.
    @discardableResult
    private func split(_ transaction: Transaction, off cents: [Int], into categoryName: String? = nil) throws -> [Transaction] {
        var draft = SplitDraft(splitting: transaction)
        for part in cents {
            var new = draft.newPart()
            new.amount = Money(cents: part)
            if let categoryName {
                new.category = try store.category(categoryName, transaction.category?.type ?? .expense)
            }
            draft.addPart(new)
        }
        return try transaction.split(draft, in: context)
    }

    private func balance() -> Money { checking.balance(asOf: today) }

    private func allTransactions() throws -> [Transaction] { try context.fetch(Transaction.notDeleted) }

    // MARK: What can be split

    @Test func anOrdinaryExpenseOrIncomeCanBeSplit() throws {
        #expect(try record(25_00).canBeSplit)
        #expect(try record(100_00, "Salary", .income).canBeSplit)
        #expect(try record(5_00, "Other Expense").canBeSplit)
    }

    @Test func aTransferHalfCannotBeSplit() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        var draft = TransferDraft(day: today)
        draft.from = checking
        draft.to = savings
        draft.amount = Money(cents: 50_00)
        let transfer = try Transfer.create(draft, in: context)

        #expect(!transfer.outgoing.canBeSplit)
        #expect(!transfer.incoming.canBeSplit)
    }

    @Test func aStartingBalanceCannotBeSplit() throws {
        let wallet = try Wallet.create(name: "Savings", startingBalance: Money(cents: 300_00), on: today, in: context)
        let startingBalance = try #require(wallet.transactions?.first)

        #expect(!startingBalance.canBeSplit)
    }

    @Test func aBalanceAdjustmentCannotBeSplit() throws {
        try record(100_00, "Salary", .income)
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: 90_00)
        let adjustment = try Transaction.adjustBalance(draft, in: context)

        #expect(!adjustment.canBeSplit)
    }

    @Test(arguments: [LockedRole.loan, .debt])
    func aLoanOrDebtAndItsPaymentsCannotBeSplit(role: LockedRole) throws {
        var draft = TransactionDraft(type: .debtLoan, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: 100_00)
        draft.category = try context.lockedCategory(role)
        draft.withName = "Pasha"
        let original = try Transaction.create(draft, in: context)
        var payment = try DebtPaymentDraft(settling: original, on: today, in: context)
        payment.amount = Money(cents: 120_00)
        let recorded = try DebtPayment.record(payment, in: context)

        let overpayment = try #require(recorded.overpayment)

        #expect(!original.canBeSplit)
        #expect(!recorded.payment.canBeSplit)
        #expect(!overpayment.canBeSplit)
    }

    @Test func aForgivenLoanCannotBeSplit() throws {
        var draft = TransactionDraft(type: .debtLoan, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: 50_00)
        draft.category = try context.lockedCategory(.loan)
        draft.withName = "Pasha"
        let loan = try Transaction.create(draft, in: context)
        let forgiveness = try ForgiveDraft(forgiving: loan, on: today, in: context)
        try Forgiveness.record(forgiveness, in: context)

        #expect(!loan.canBeSplit)
    }

    @Test func aTransactionInRecentlyDeletedCannotBeSplit() throws {
        let coffee = try record(25_00)
        try coffee.delete(.onlySelected, in: context)

        #expect(!coffee.canBeSplit)
    }

    @Test func splittingAnIneligibleTransactionIsRefusedAndChangesNothing() throws {
        let wallet = try Wallet.create(name: "Savings", startingBalance: Money(cents: 300_00), on: today, in: context)
        let startingBalance = try #require(wallet.transactions?.first)
        var draft = SplitDraft(splitting: startingBalance)
        draft.addPart(draft.newPart())

        #expect(throws: SplitRuleError.notSplittable) { try startingBalance.split(draft, in: context) }
        #expect(startingBalance.linkID == nil)
        #expect(wallet.transactions?.count == 1)
    }

    // MARK: Making a split

    @Test func eachPartStartsAsACopyOfTheTransaction() throws {
        let card = try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
        let coffee = try record(25_00, card: card)
        coffee.note = "Brunch"
        coffee.withName = "Anna"
        coffee.eventName = "Trip"
        coffee.isExcludedFromReport = true

        let part = try #require(try split(coffee, off: [10_00]).first)

        #expect(part.wallet == checking)
        #expect(part.card == card)
        #expect(part.category == coffee.category)
        #expect(part.day == today)
        #expect(part.note == "Brunch")
        #expect(part.withName == "Anna")
        #expect(part.eventName == "Trip")
        #expect(part.isExcludedFromReport)
        #expect(part.recurring == nil)
        #expect(part.amountCents == -10_00)
    }

    @Test func theOriginalIsAlwaysTheRemainder() throws {
        let coffee = try record(25_00)

        try split(coffee, off: [10_00, 5_00, 3_50])

        #expect(coffee.amountCents == -6_50)
    }

    @Test func theOriginalUpdatesLiveAsPartsAreAddedChangedAndRemoved() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        #expect(draft.original.amount == Money(cents: 25_00))

        var first = draft.newPart()
        first.amount = Money(cents: 10_00)
        draft.addPart(first)
        #expect(draft.original.amount == Money(cents: 15_00))

        var second = draft.newPart()
        second.amount = Money(cents: 4_00)
        draft.addPart(second)
        #expect(draft.original.amount == Money(cents: 11_00))

        first.amount = Money(cents: 12_00)
        draft.replacePart(at: 0, with: first)
        #expect(draft.original.amount == Money(cents: 9_00))

        draft.removePart(at: 1)
        #expect(draft.original.amount == Money(cents: 13_00))
        #expect(draft.total == Money(cents: 25_00))
    }

    @Test func aNewPartStartsAtZeroAsACopyOfTheOriginal() throws {
        let coffee = try record(25_00)
        coffee.note = "Brunch"
        coffee.withName = "Anna"
        var draft = SplitDraft(splitting: coffee)
        draft.original.category = try store.category("Education")

        let part = draft.newPart()

        #expect(part.amount == Money(cents: 0))
        #expect(part.category == draft.original.category)
        #expect(part.day == today)
        #expect(part.note == "Brunch")
        #expect(part.withName == "Anna")
    }

    @Test func theOriginalKeepsItsIdentityCreatedAtAndRecurringAttachment() throws {
        let category = try store.category("Café")
        var schedule = RecurringDraft(startDay: today)
        schedule.name = "Coffee"
        schedule.amount = Money(cents: 25_00)
        schedule.wallet = checking
        schedule.category = category
        let recurring = try RecurringTransaction.create(schedule, today: today, in: context)
        let coffee = try record(25_00)
        try recurring.attach(coffee, in: context)
        let createdAt = coffee.createdAt
        let identity = coffee.persistentModelID

        let parts = try split(coffee, off: [10_00])

        #expect(coffee.persistentModelID == identity)
        #expect(coffee.createdAt == createdAt)
        #expect(coffee.recurring == recurring)
        #expect(parts.allSatisfy { $0.recurring == nil && $0.createdAt >= createdAt })
    }

    @Test func thePartsShareALinkAndAreEachOthersRelatedTransactions() throws {
        let coffee = try record(25_00)
        let other = try record(7_00)

        let parts = try split(coffee, off: [10_00, 5_00])

        let link = try #require(coffee.linkID)
        #expect(parts.allSatisfy { $0.linkID == link })
        #expect(try Set(coffee.related(in: context)) == Set(parts))
        #expect(try Set(parts[0].related(in: context)) == [coffee, parts[1]])
        #expect(other.linkID == nil)
    }

    @Test func nothingInTheBalanceOrTheReportChangesWhenThePartsSumToTheOriginal() throws {
        try record(1_000_00, "Salary", .income)
        let coffee = try record(25_00)
        func spent() throws -> Money {
            try PeriodTotals(
                of: allTransactions(), in: .total, period: .month(CalendarMonth(today)), today: today
            ).spent
        }
        let balanceBefore = balance()
        let spentBefore = try spent()

        try split(coffee, off: [10_00, 5_00], into: "Education")

        #expect(balance() == balanceBefore)
        #expect(try spent() == spentBefore)
    }

    @Test func eachPartCanChangeItsAmountCategoryDayNoteWithAndEvent() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        part.category = try store.category("Education")
        part.day = today.adding(days: -2)
        part.note = "  Milk \n"
        part.withName = " Anna "
        part.eventName = " Trip "
        draft.addPart(part)
        draft.original.note = "Latte"
        draft.original.withName = "Pasha"
        draft.original.eventName = "Wedding"
        draft.original.category = try store.category("Restaurants")
        draft.original.day = today.adding(days: 1)

        let created = try #require(try coffee.split(draft, in: context).first)

        #expect(created.amountCents == -10_00)
        #expect(created.category == (try store.category("Education")))
        #expect(created.day == today.adding(days: -2))
        #expect(created.note == "Milk")
        #expect(created.withName == "Anna")
        #expect(created.eventName == "Trip")
        #expect(coffee.amountCents == -15_00)
        #expect(coffee.note == "Latte")
        #expect(coffee.withName == "Pasha")
        #expect(coffee.eventName == "Wedding")
        #expect(coffee.category == (try store.category("Restaurants")))
        #expect(coffee.day == today.adding(days: 1))
    }

    @Test func theWalletAndCardAreSharedByEveryPart() throws {
        let card = try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
        let coffee = try record(25_00, card: card)

        let parts = try split(coffee, off: [10_00, 5_00])

        #expect(parts.allSatisfy { $0.wallet == checking && $0.card == card })
        #expect(coffee.wallet == checking && coffee.card == card)
    }

    // MARK: Changing the total

    @Test func typingOverTheOriginalChangesTheTotalAndMovesTheBalanceByTheDifference() throws {
        let coffee = try record(25_00)
        let balanceBefore = balance()
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)

        // The original shows 15.00; the user types 16.80 over it.
        draft.original.amount = Money(cents: 16_80)

        #expect(draft.was == Money(cents: 25_00))
        #expect(draft.total == Money(cents: 26_80))
        #expect(draft.walletChange == Money(cents: -1_80))
        try coffee.split(draft, in: context)
        #expect(coffee.amountCents == -16_80)
        #expect(balance() == Money(cents: balanceBefore.cents - 1_80))
    }

    @Test func theTotalIsUnchangedWhileThePartsSumToTheOriginal() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)

        #expect(draft.total == draft.was)
        #expect(draft.walletChange == Money(cents: 0))
    }

    @Test func anIncomeSplitKeepsEveryPartPositiveAndAHigherTotalRaisesTheBalance() throws {
        let salary = try record(100_00, "Salary", .income)
        let balanceBefore = balance()
        var draft = SplitDraft(splitting: salary)
        var part = draft.newPart()
        part.amount = Money(cents: 30_00)
        draft.addPart(part)
        draft.original.amount = Money(cents: 75_00)

        #expect(draft.walletChange == Money(cents: 5_00))
        let created = try #require(try salary.split(draft, in: context).first)

        #expect(created.amountCents == 30_00)
        #expect(salary.amountCents == 75_00)
        #expect(balance() == Money(cents: balanceBefore.cents + 5_00))
    }

    @Test func aLowerTotalOnAnExpenseGivesBackToTheBalance() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)
        draft.original.amount = Money(cents: 12_00)

        #expect(draft.walletChange == Money(cents: 3_00))
    }

    @Test func changingTheTotalConfirmsAnEstimatedAmount() throws {
        let coffee = try record(25_00)
        coffee.isEstimated = true
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)
        draft.original.amount = Money(cents: 16_00)

        try coffee.split(draft, in: context)

        #expect(!coffee.isEstimated)
    }

    // MARK: Required fields

    @Test func aSplitWithoutAnyPartIsRefused() throws {
        let coffee = try record(25_00)
        let draft = SplitDraft(splitting: coffee)

        #expect(!draft.canSplit)
        #expect(throws: SplitRuleError.noParts) { try coffee.split(draft, in: context) }
        #expect(coffee.linkID == nil)
    }

    @Test func aPartWithoutAnAmountIsRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        draft.addPart(draft.newPart())

        #expect(!draft.canSplit)
        #expect(throws: SplitRuleError.missingAmount) { try coffee.split(draft, in: context) }
        #expect(try allTransactions().count == 1)
    }

    @Test func partsThatLeaveNothingOrLessOnTheOriginalAreRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 25_00)
        draft.addPart(part)

        #expect(draft.original.amount == Money(cents: 0))
        #expect(throws: SplitRuleError.missingAmount) { try coffee.split(draft, in: context) }
        #expect(coffee.amountCents == -25_00)
        #expect(try allTransactions().count == 1)
    }

    @Test func aPartWithoutACategoryIsRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        part.category = nil
        draft.addPart(part)

        #expect(throws: SplitRuleError.missingCategory) { try coffee.split(draft, in: context) }
        #expect(coffee.amountCents == -25_00)
    }

    // MARK: Parts are independent

    @Test func aPartIsEditedInTheAddSheetWithoutTouchingTheOthers() throws {
        let coffee = try record(25_00)
        let part = try #require(try split(coffee, off: [10_00]).first)
        let balanceBefore = balance()

        #expect(part.editFlow == .addSheet)
        #expect(coffee.editFlow == .addSheet)
        var edit = TransactionDraft(editing: part)
        edit.amount = Money(cents: 12_00)
        edit.note = "Milk"
        try part.update(with: edit)

        #expect(part.amountCents == -12_00)
        #expect(coffee.amountCents == -15_00)
        #expect(coffee.note.isEmpty)
        #expect(balance() == Money(cents: balanceBefore.cents - 2_00))
    }

    @Test func aPartCanBeMovedBetweenExpenseAndIncomeButNeverToDebtOrLoan() throws {
        let coffee = try record(25_00)
        let part = try #require(try split(coffee, off: [10_00]).first)

        #expect(TransactionDraft(editing: part).types == [.expense, .income])
        #expect(TransactionDraft(editing: coffee).types == [.expense, .income])
        #expect(TransactionDraft(duplicating: coffee, on: today).types == CategoryType.segments)
    }

    @Test func aPartOfAnExpenseInACardWalletKeepsTheCardRule() throws {
        let card = try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
        let coffee = try record(25_00, card: card)
        let part = try #require(try split(coffee, off: [10_00]).first)

        #expect(part.cardRuleExemption == nil)
        #expect(TransactionDraft(editing: part).requiresCard)
    }

    @Test func whatAnOverpaymentWritesOffIsStillNotASplitPart() throws {
        var draft = TransactionDraft(type: .debtLoan, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: 100_00)
        draft.category = try context.lockedCategory(.debt)
        draft.withName = "Anna"
        let debt = try Transaction.create(draft, in: context)
        var payment = try DebtPaymentDraft(settling: debt, on: today, in: context)
        payment.amount = Money(cents: 120_00)
        let overpaid = try #require(try DebtPayment.record(payment, in: context).overpayment)

        #expect(overpaid.isDebtWriteOff)
        #expect(!overpaid.isSplitPart)
        #expect(overpaid.editFlow == nil)
    }

    @Test func aPartCanBeSplitAgainAndJoinsTheSameSplit() throws {
        let coffee = try record(25_00)
        let first = try #require(try split(coffee, off: [10_00]).first)

        let second = try #require(try split(first, off: [4_00]).first)

        #expect(second.linkID == coffee.linkID)
        #expect(first.amountCents == -6_00)
        #expect(try Set(coffee.related(in: context)) == [first, second])
    }

    // MARK: Deleting a part

    @Test func deletingOnePartLeavesTheOthersAndTakesItsAmountOutOfTheBalance() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        let balanceBefore = balance()

        try parts[0].delete(.onlySelected, in: context)

        #expect(try coffee.related(in: context) == [parts[1]])
        #expect(balance() == Money(cents: balanceBefore.cents + 10_00))
    }

    // MARK: Undo split

    @Test func undoSplitMergesEveryPartBackIntoTheOriginalSummingTheirAmounts() throws {
        let coffee = try record(25_00)
        let balanceBefore = balance()
        let parts = try split(coffee, off: [10_00, 5_00])
        let identity = coffee.persistentModelID

        try parts[1].undoSplit(in: context)

        #expect(try allTransactions().contains { $0.persistentModelID == identity })
        #expect(try allTransactions().count == 1)
        #expect(coffee.amountCents == -25_00)
        #expect(coffee.linkID == nil)
        #expect(try coffee.related(in: context).isEmpty)
        #expect(balance() == balanceBefore)
    }

    @Test func undoSplitSumsTheAmountsAsTheyAreNowIncludingAChangedTotal() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)
        draft.original.amount = Money(cents: 16_80)
        let created = try #require(try coffee.split(draft, in: context).first)
        created.amountCents = -9_00

        try coffee.undoSplit(in: context)

        #expect(coffee.amountCents == -25_80)
        #expect(balance() == Money(cents: -25_80))
    }

    @Test func undoSplitOfAnIncomeKeepsItPositive() throws {
        let salary = try record(100_00, "Salary", .income)
        let parts = try split(salary, off: [30_00, 20_00])

        try parts[0].undoSplit(in: context)

        #expect(salary.amountCents == 100_00)
    }

    @Test func undoSplitKeepsTheOriginalsOwnFieldsAndRecurringAttachment() throws {
        let category = try store.category("Café")
        var schedule = RecurringDraft(startDay: today)
        schedule.name = "Coffee"
        schedule.amount = Money(cents: 25_00)
        schedule.wallet = checking
        schedule.category = category
        let recurring = try RecurringTransaction.create(schedule, today: today, in: context)
        let coffee = try record(25_00)
        try recurring.attach(coffee, in: context)
        coffee.note = "Brunch"
        let parts = try split(coffee, off: [10_00], into: "Education")

        try parts[0].undoSplit(in: context)

        #expect(coffee.category == category)
        #expect(coffee.note == "Brunch")
        #expect(coffee.recurring == recurring)
    }

    @Test func undoSplitLeavesPartsInRecentlyDeletedWhereTheyAreAndDoesNotCountThem() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        try parts[0].delete(.onlySelected, in: context)

        try coffee.undoSplit(in: context)

        // What is left of the original and the part that was not deleted: 10.00 + 5.00 less the deleted 10.00.
        #expect(coffee.amountCents == -15_00)
        #expect(try allTransactions().count == 1)
        #expect(parts[0].isInRecentlyDeleted)
        #expect(try RecentlyDeleted(in: context).transactions == [parts[0]])
    }

    @Test func undoSplitIsRefusedForATransactionThatIsNotSplit() throws {
        let coffee = try record(25_00)

        #expect(throws: SplitRuleError.notSplit) { try coffee.undoSplit(in: context) }
    }

    @Test func undoSplitIsRefusedOnceEveryOtherPartIsDeleted() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00])
        try parts[0].delete(.onlySelected, in: context)

        #expect(throws: SplitRuleError.notSplit) { try coffee.undoSplit(in: context) }
        #expect(coffee.amountCents == -15_00)
    }

    @Test func undoSplitMergesTheRemainingPartsWhenTheOriginalWasDeleted() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        try coffee.delete(.onlySelected, in: context)

        try parts[1].undoSplit(in: context)

        let merged = try #require(try allTransactions().first)
        #expect(try allTransactions().count == 1)
        #expect(merged.amountCents == -15_00)
        #expect(merged.linkID == nil)
    }

    @Test func undoSplitOfASplitSplitMergesEveryPart() throws {
        let coffee = try record(25_00)
        let first = try #require(try split(coffee, off: [10_00]).first)
        try split(first, off: [4_00])

        try first.undoSplit(in: context)

        #expect(try allTransactions() == [coffee])
        #expect(coffee.amountCents == -25_00)
    }
}
