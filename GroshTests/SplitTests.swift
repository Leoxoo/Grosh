import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Split: dividing an Expense or Income into linked parts that each take their own amount, category, day, note, With
/// and Event, and Undo split, which merges them back.
@MainActor
@Suite(.namedInTheLog)
struct SplitTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private let today = TestStore.today

    init() throws {
        store = try TestStore()
    }

    /// An Expense (unless `type` says Income) of `cents` under `categoryName`, dated today in Checking, saved through
    /// the Add sheet's draft.
    @discardableResult
    private func record(
        _ cents: Int, _ categoryName: String = "Café", _ type: CategoryType = .expense, card: Card? = nil
    ) throws -> Transaction {
        var draft = TransactionDraft(type: type, day: today)
        draft.wallet = checking
        draft.entry = AmountEntry(cents: cents)
        draft.category = try store.category(categoryName, type)
        draft.card = card
        return try Transaction.create(draft, in: context)
    }

    /// Assigns `reimbursement` to `part` in `draft`.
    private func assign(_ reimbursement: Reimbursement, to part: SplitPartRef?, in draft: inout SplitDraft) throws {
        let index = try #require(draft.reimbursements.firstIndex { $0.reimbursement === reimbursement })
        draft.reimbursements[index].part = part
    }

    /// The part `draft` sends `reimbursement` to, `nil` while it is unassigned.
    private func assignment(of reimbursement: Reimbursement, in draft: SplitDraft) -> SplitPartRef? {
        draft.reimbursements.first { $0.reimbursement === reimbursement }?.part
    }

    /// Splits `transaction`, adding a part for each of `cents`, filed under `categoryName` when one is given, and
    /// sending each Reimbursement in `sending` to its part.
    @discardableResult
    private func split(
        _ transaction: Transaction, off cents: [Int], into categoryName: String? = nil,
        sending reimbursements: [(Reimbursement, SplitPartRef)] = []
    ) throws -> [Transaction] {
        var draft = SplitDraft(splitting: transaction)
        for (reimbursement, part) in reimbursements {
            try assign(reimbursement, to: part, in: &draft)
        }
        for part in cents {
            var new = draft.newPart()
            new.entry = AmountEntry(cents: part)
            if let categoryName {
                new.category = try store.category(categoryName, transaction.category?.type ?? .expense)
            }
            draft.addPart(new)
        }
        return try transaction.split(draft)
    }

    private func balance() -> Money { walletBalance(checking, asOf: today) }

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
        draft.entry = AmountEntry(cents: 50_00)
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
        let original = try context.recordLoanOrDebt(
            role, 100_00, with: context.person("Pasha"), on: today, in: checking
        )
        let recorded = try context.pay(120_00, on: original, on: today)

        let overpayment = try #require(recorded.overpayment)

        #expect(!original.canBeSplit)
        #expect(!recorded.payment.canBeSplit)
        #expect(!overpayment.canBeSplit)
    }

    @Test func aForgivenLoanCannotBeSplit() throws {
        let loan = try context.recordLoanOrDebt(
            .loan, 50_00, with: context.person("Pasha"), on: today, in: checking
        )
        try context.forgive(loan, on: today)

        #expect(!loan.canBeSplit)
    }

    @Test func aTransactionInRecentlyDeletedCannotBeSplit() throws {
        let coffee = try record(25_00)
        try coffee.delete(.onlySelected)

        #expect(!coffee.canBeSplit)
    }

    @Test func splittingAnIneligibleTransactionIsRefusedAndChangesNothing() throws {
        let wallet = try Wallet.create(name: "Savings", startingBalance: Money(cents: 300_00), on: today, in: context)
        let startingBalance = try #require(wallet.transactions?.first)
        var draft = SplitDraft(splitting: startingBalance)
        draft.addPart(draft.newPart())

        #expect(throws: SplitRuleError.notSplittable) { try startingBalance.split(draft) }
        #expect(startingBalance.linkID == nil)
        #expect(wallet.transactions?.count == 1)
    }

    // MARK: Making a split

    @Test func eachPartStartsAsACopyOfTheTransaction() throws {
        let card = try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
        let coffee = try record(25_00, card: card)
        coffee.note = "Brunch"
        coffee.setPeople([try Person.add(named: "Anna", in: context)])
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
        first.entry = AmountEntry(cents: 10_00)
        draft.addPart(first)
        #expect(draft.original.amount == Money(cents: 15_00))

        var second = draft.newPart()
        second.entry = AmountEntry(cents: 4_00)
        draft.addPart(second)
        #expect(draft.original.amount == Money(cents: 11_00))

        first.entry = AmountEntry(cents: 12_00)
        draft.replacePart(at: 0, with: first)
        #expect(draft.original.amount == Money(cents: 9_00))

        draft.removePart(at: 1)
        #expect(draft.original.amount == Money(cents: 13_00))
        #expect(draft.total == Money(cents: 25_00))
    }

    @Test func aNewPartStartsAtZeroAsACopyOfTheOriginal() throws {
        let coffee = try record(25_00)
        coffee.note = "Brunch"
        coffee.setPeople([try Person.add(named: "Anna", in: context)])
        var draft = SplitDraft(splitting: coffee)
        draft.original.category = try store.category("Education")

        let part = draft.newPart()

        #expect(part.amount == Money(cents: 0))
        #expect(part.category == draft.original.category)
        #expect(part.day == today)
        #expect(part.note == "Brunch")
        #expect(part.people.map(\.name) == ["Anna"])
    }

    @Test func theOriginalKeepsItsIdentityCreatedAtAndRecurringAttachment() throws {
        let category = try store.category("Café")
        let schedule = store.recurringDraft("Coffee", 25_00, under: category, starting: today)
        let recurring = try RecurringTransaction.create(schedule, today: today, in: context)
        let coffee = try record(25_00)
        try recurring.attach(coffee)
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
        #expect(try Set(coffee.related()) == Set(parts))
        #expect(try Set(parts[0].related()) == [coffee, parts[1]])
        #expect(other.linkID == nil)
    }

    @Test func nothingInTheBalanceOrTheReportChangesWhenThePartsSumToTheOriginal() throws {
        try record(1_000_00, "Salary", .income)
        let coffee = try record(25_00)
        func spent() throws -> Money {
            try store.totals(of: .month(CalendarMonth(today)), today: today).spent
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
        part.entry = AmountEntry(cents: 10_00)
        part.category = try store.category("Education")
        part.day = today.adding(days: -2)
        part.note = "  Milk \n"
        part.people = [try Person.add(named: " Anna ", in: context)]
        part.eventName = " Trip "
        draft.addPart(part)
        draft.original.note = "Latte"
        draft.original.people = [try Person.add(named: "Pasha", in: context)]
        draft.original.eventName = "Wedding"
        draft.original.category = try store.category("Restaurants")
        draft.original.day = today.adding(days: 1)

        let created = try #require(try coffee.split(draft).first)

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
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)

        // The original shows 15.00; the user types 16.80 over it.
        draft.original.entry = AmountEntry(cents: 16_80)

        #expect(draft.was == Money(cents: 25_00))
        #expect(draft.total == Money(cents: 26_80))
        #expect(draft.walletChange == Money(cents: -1_80))
        try coffee.split(draft)
        #expect(coffee.amountCents == -16_80)
        #expect(balance() == Money(cents: balanceBefore.cents - 1_80))
    }

    @Test func theTotalIsUnchangedWhileThePartsSumToTheOriginal() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)

        #expect(draft.total == draft.was)
        #expect(draft.walletChange == Money(cents: 0))
    }

    @Test func anIncomeSplitKeepsEveryPartPositiveAndAHigherTotalRaisesTheBalance() throws {
        let salary = try record(100_00, "Salary", .income)
        let balanceBefore = balance()
        var draft = SplitDraft(splitting: salary)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 30_00)
        draft.addPart(part)
        draft.original.entry = AmountEntry(cents: 75_00)

        #expect(draft.walletChange == Money(cents: 5_00))
        let created = try #require(try salary.split(draft).first)

        #expect(created.amountCents == 30_00)
        #expect(salary.amountCents == 75_00)
        #expect(balance() == Money(cents: balanceBefore.cents + 5_00))
    }

    @Test func aLowerTotalOnAnExpenseGivesBackToTheBalance() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)
        draft.original.entry = AmountEntry(cents: 12_00)

        #expect(draft.walletChange == Money(cents: 3_00))
    }

    @Test func changingTheTotalConfirmsAnEstimatedAmount() throws {
        let coffee = try record(25_00)
        coffee.isEstimated = true
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)
        draft.original.entry = AmountEntry(cents: 16_00)

        try coffee.split(draft)

        #expect(!coffee.isEstimated)
    }

    @Test func splittingWithoutChangingTheTotalKeepsAnEstimatedAmountEstimated() throws {
        let coffee = try record(25_00)
        coffee.isEstimated = true

        try split(coffee, off: [10_00, 5_00])

        #expect(coffee.isEstimated)
        #expect(coffee.amountCents == -10_00)
    }

    // MARK: Required fields

    @Test func aSplitWithoutAnyPartIsRefused() throws {
        let coffee = try record(25_00)
        let draft = SplitDraft(splitting: coffee)

        #expect(!draft.canSave)
        #expect(throws: SplitRuleError.noParts) { try coffee.split(draft) }
        #expect(coffee.linkID == nil)
    }

    @Test func aPartWithoutAnAmountIsRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        draft.addPart(draft.newPart())

        #expect(!draft.canSave)
        #expect(throws: SplitRuleError.missingAmount) { try coffee.split(draft) }
        #expect(try allTransactions().count == 1)
    }

    @Test func partsThatLeaveNothingOrLessOnTheOriginalAreRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 25_00)
        draft.addPart(part)

        #expect(draft.original.amount == Money(cents: 0))
        #expect(throws: SplitRuleError.missingAmount) { try coffee.split(draft) }
        #expect(coffee.amountCents == -25_00)
        #expect(try allTransactions().count == 1)
    }

    @Test func aPartWithoutACategoryIsRefused() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        part.category = nil
        draft.addPart(part)

        #expect(throws: SplitRuleError.missingCategory) { try coffee.split(draft) }
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
        edit.entry = AmountEntry(cents: 12_00)
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

    @Test func theStoredLinkKindTellsPartsFromWriteOffs() throws {
        let debt = try context.recordLoanOrDebt(
            .debt, 100_00, with: context.person("Anna"), on: today, in: checking
        )
        let overpaid = try #require(try context.pay(120_00, on: debt, on: today).overpayment)
        let coffee = try record(25_00)
        let part = try #require(try split(coffee, off: [10_00]).first)
        // A Debt in Recently Deleted still holds its link.
        try debt.delete(.onlySelected)

        #expect(overpaid.linkKind == .loanOrDebt && debt.linkKind == .loanOrDebt)
        #expect(overpaid.isDebtWriteOff && !overpaid.isSplitPart)
        #expect(overpaid.editFlow == nil)
        for transaction in [coffee, part] {
            #expect(transaction.linkKind == .split)
            #expect(transaction.isSplitPart && !transaction.isDebtWriteOff)
        }
    }

    @Test func aPartCanBeSplitAgainAndJoinsTheSameSplit() throws {
        let coffee = try record(25_00)
        let first = try #require(try split(coffee, off: [10_00]).first)

        let second = try #require(try split(first, off: [4_00]).first)

        #expect(second.linkID == coffee.linkID)
        #expect(first.amountCents == -6_00)
        #expect(try Set(coffee.related()) == [first, second])
    }

    // MARK: Deleting a part

    @Test func deletingOnePartLeavesTheOthersAndTakesItsAmountOutOfTheBalance() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        let balanceBefore = balance()

        try parts[0].delete(.onlySelected)

        #expect(try coffee.related() == [parts[1]])
        #expect(balance() == Money(cents: balanceBefore.cents + 10_00))
    }

    // MARK: Undo split

    @Test func undoSplitMergesEveryPartBackIntoTheOriginalSummingTheirAmounts() throws {
        let coffee = try record(25_00)
        let balanceBefore = balance()
        let parts = try split(coffee, off: [10_00, 5_00])
        let identity = coffee.persistentModelID

        try parts[1].undoSplit()

        #expect(try allTransactions().contains { $0.persistentModelID == identity })
        #expect(try allTransactions().count == 1)
        #expect(coffee.amountCents == -25_00)
        #expect(coffee.linkID == nil)
        #expect(try coffee.related().isEmpty)
        #expect(balance() == balanceBefore)
    }

    @Test func undoSplitSumsTheAmountsAsTheyAreNowIncludingAChangedTotal() throws {
        let coffee = try record(25_00)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)
        draft.original.entry = AmountEntry(cents: 16_80)
        let created = try #require(try coffee.split(draft).first)
        created.amountCents = -9_00

        try coffee.undoSplit()

        #expect(coffee.amountCents == -25_80)
        #expect(balance() == Money(cents: -25_80))
    }

    @Test func undoSplitOfAnIncomeKeepsItPositive() throws {
        let salary = try record(100_00, "Salary", .income)
        let parts = try split(salary, off: [30_00, 20_00])

        try parts[0].undoSplit()

        #expect(salary.amountCents == 100_00)
    }

    @Test func undoSplitKeepsTheOriginalsOwnFieldsAndRecurringAttachment() throws {
        let category = try store.category("Café")
        let schedule = store.recurringDraft("Coffee", 25_00, under: category, starting: today)
        let recurring = try RecurringTransaction.create(schedule, today: today, in: context)
        let coffee = try record(25_00)
        try recurring.attach(coffee)
        coffee.note = "Brunch"
        let parts = try split(coffee, off: [10_00], into: "Education")

        try parts[0].undoSplit()

        #expect(coffee.category == category)
        #expect(coffee.note == "Brunch")
        #expect(coffee.recurring == recurring)
    }

    @Test func undoSplitLeavesPartsInRecentlyDeletedWhereTheyAreAndDoesNotCountThem() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        try parts[0].delete(.onlySelected)

        try coffee.undoSplit()

        // What is left of the original and the part that was not deleted: 10.00 + 5.00 less the deleted 10.00.
        #expect(coffee.amountCents == -15_00)
        #expect(try allTransactions().count == 1)
        #expect(parts[0].isInRecentlyDeleted)
        #expect(try RecentlyDeleted(in: context).transactions == [parts[0]])
    }

    @Test func undoSplitIsRefusedForATransactionThatIsNotSplit() throws {
        let coffee = try record(25_00)

        #expect(throws: SplitRuleError.notSplit) { try coffee.undoSplit() }
    }

    @Test func undoSplitIsRefusedOnceEveryOtherPartIsDeleted() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00])
        try parts[0].delete(.onlySelected)

        #expect(throws: SplitRuleError.notSplit) { try coffee.undoSplit() }
        #expect(coffee.amountCents == -15_00)
    }

    @Test func undoSplitMergesTheRemainingPartsWhenTheOriginalWasDeleted() throws {
        let coffee = try record(25_00)
        let parts = try split(coffee, off: [10_00, 5_00])
        try coffee.delete(.onlySelected)

        try parts[1].undoSplit()

        let merged = try #require(try allTransactions().first)
        #expect(try allTransactions().count == 1)
        #expect(merged.amountCents == -15_00)
        #expect(merged.linkID == nil)
    }

    @Test func undoSplitOfASplitSplitMergesEveryPart() throws {
        let coffee = try record(25_00)
        let first = try #require(try split(coffee, off: [10_00]).first)
        try split(first, off: [4_00])

        try first.undoSplit()

        #expect(try allTransactions() == [coffee])
        #expect(coffee.amountCents == -25_00)
    }

    // MARK: Reimbursements

    @Test func anExpenseWithoutReimbursementsHasNothingToAssign() throws {
        let coffee = try record(25_00)

        #expect(SplitDraft(splitting: coffee).reimbursements.isEmpty)
    }

    @Test func saveWaitsUntilEveryReimbursementIsAssignedToAPart() throws {
        let coffee = try record(25_00)
        let first = try context.payBack(5_00, on: today, to: coffee)
        let second = try context.payBack(3_00, on: today, to: coffee)
        var draft = SplitDraft(splitting: coffee)
        var part = draft.newPart()
        part.entry = AmountEntry(cents: 10_00)
        draft.addPart(part)

        #expect(draft.reimbursements.count == 2)
        #expect(!draft.canSave)
        #expect(throws: SplitRuleError.unassignedReimbursement) { try coffee.split(draft) }
        #expect(coffee.linkID == nil)
        #expect(try allTransactions().count == 1)

        try assign(first, to: .part(0), in: &draft)
        #expect(!draft.canSave)
        try assign(second, to: .original, in: &draft)
        #expect(draft.canSave)
    }

    @Test func splittingSendsEachReimbursementToThePartItWasAssignedTo() throws {
        let coffee = try record(25_00)
        let first = try context.payBack(5_00, on: today, to: coffee)
        let second = try context.payBack(3_00, on: today, to: coffee)
        let third = try context.payBack(2_00, on: today, to: coffee)
        let balanceBefore = balance()

        let parts = try split(
            coffee, off: [10_00, 5_00], sending: [(first, .part(0)), (second, .original), (third, .part(0))]
        )

        #expect(coffee.orderedReimbursements == [second])
        #expect(parts[0].orderedReimbursements == [first, third])
        #expect(parts[1].orderedReimbursements.isEmpty)
        #expect(first.expense == parts[0])
        #expect(coffee.netCents == -7_00)
        #expect(parts[0].netCents == -3_00)
        #expect(parts[1].netCents == -5_00)
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 3)
        #expect(balance() == balanceBefore)
    }

    @Test func removingAPartUnassignsItsReimbursementsAndKeepsTheOthersOnTheirParts() throws {
        let coffee = try record(25_00)
        let onFirst = try context.payBack(1_00, on: today, to: coffee)
        let onSecond = try context.payBack(2_00, on: today, to: coffee)
        let onThird = try context.payBack(3_00, on: today, to: coffee)
        let onOriginal = try context.payBack(4_00, on: today, to: coffee)
        var draft = SplitDraft(splitting: coffee)
        for cents in [10_00, 5_00, 3_00] {
            var part = draft.newPart()
            part.entry = AmountEntry(cents: cents)
            draft.addPart(part)
        }
        try assign(onFirst, to: .part(0), in: &draft)
        try assign(onSecond, to: .part(1), in: &draft)
        try assign(onThird, to: .part(2), in: &draft)
        try assign(onOriginal, to: .original, in: &draft)
        #expect(draft.canSave)

        draft.removePart(at: 1)

        #expect(assignment(of: onFirst, in: draft) == .part(0))
        #expect(assignment(of: onSecond, in: draft) == nil)
        #expect(assignment(of: onThird, in: draft) == .part(1))
        #expect(assignment(of: onOriginal, in: draft) == .original)
        #expect(!draft.canSave)
    }

    @Test func undoSplitMovesEveryPartsReimbursementsBackOntoTheOriginal() throws {
        let coffee = try record(25_00)
        let first = try context.payBack(5_00, on: today, to: coffee)
        let second = try context.payBack(3_00, on: today, to: coffee)
        let third = try context.payBack(2_00, on: today, to: coffee)
        let balanceBefore = balance()
        let parts = try split(
            coffee, off: [10_00, 5_00], sending: [(first, .part(0)), (second, .part(1)), (third, .original)]
        )

        try parts[1].undoSplit()

        #expect(try allTransactions() == [coffee])
        #expect(Set(coffee.orderedReimbursements) == [first, second, third])
        #expect(coffee.netCents == -15_00)
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 3)
        #expect(balance() == balanceBefore)
    }

    @Test func aPartSplitAgainSendsItsReimbursementsToTheNewPart() throws {
        let coffee = try record(25_00)
        let reimbursement = try context.payBack(5_00, on: today, to: coffee)
        let first = try #require(try split(coffee, off: [10_00], sending: [(reimbursement, .part(0))]).first)

        let second = try #require(try split(first, off: [4_00], sending: [(reimbursement, .part(0))]).first)

        #expect(reimbursement.expense == second)
        #expect(first.orderedReimbursements.isEmpty)
        try first.undoSplit()
        #expect(coffee.orderedReimbursements == [reimbursement])
    }

    // MARK: People in With

    @Test func eachPartCanBeWithSeveralPeople() throws {
        let coffee = try record(25_00)
        let anna = try Person.add(named: "Anna", in: context)
        let ivan = try Person.add(named: "Ivan", in: context)
        coffee.setPeople([anna])
        var draft = SplitDraft(splitting: coffee)
        #expect(draft.original.people == [anna])
        var part = draft.newPart()
        #expect(part.people == [anna])
        part.entry = AmountEntry(cents: 10_00)
        part.people = [anna, ivan]
        draft.addPart(part)

        let created = try #require(try coffee.split(draft).first)

        #expect(created.orderedPeople.map(\.name) == ["Anna", "Ivan"])
        #expect(created.withName == "Anna; Ivan")
        #expect(coffee.orderedPeople == [anna])
    }
}
