import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Moving an existing deposit into an Expense as a Reimbursement: the deposit's amount, day and note become the entry, and
/// the deposit goes to Recently Deleted. Also how the row lists an Expense's entries.
@MainActor
@Suite(.namedInTheLog)
struct ReimbursementMovingInTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private let deletedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let unitedStates = Locale(identifier: "en_US")

    init() throws {
        store = try MonthGraphFixture()
    }

    private func deposit(_ cents: Int = 25_00, note: String = "") throws -> Transaction {
        let deposit = try store.record(cents, "Tips", .income, on: day(2026, 10, 5))
        deposit.note = note
        return deposit
    }

    // MARK: Moving in

    @Test func aDepositsAmountDayAndNoteBecomeTheDraft() throws {
        let draft = ReimbursementDraft(movingIn: try deposit(note: "Sam's share"))

        #expect(draft.amount == Money(cents: 25_00))
        #expect(draft.day == day(2026, 10, 5))
        #expect(draft.note == "Sam's share")
    }

    @Test func movingADepositInMakesAReimbursementOfItsAmountDayAndNote() throws {
        let dinner = try store.dinner()

        let entry = try Reimbursement.moveIn(try deposit(note: "Sam's share"), to: dinner, in: context)

        #expect(dinner.orderedReimbursements == [entry])
        #expect(entry.amountCents == 25_00)
        #expect(entry.day == day(2026, 10, 5))
        #expect(entry.note == "Sam's share")
        #expect(dinner.netCents == -35_00)
    }

    @Test func movingADepositInSendsItToRecentlyDeleted() throws {
        let deposit = try deposit()

        try Reimbursement.moveIn(deposit, to: try store.dinner(), in: context, at: deletedAt)

        #expect(deposit.isInRecentlyDeleted)
        #expect(deposit.deletedAt == deletedAt)
        #expect(try RecentlyDeleted(in: context).transactions == [deposit])
    }

    @Test func theMovedDepositCountsOnceInTheBalance() throws {
        let dinner = try store.dinner()
        let deposit = try deposit()
        let today = store.today
        try context.save()
        #expect(walletBalance(store.checking, asOf: today) == Money(cents: -35_00))

        try Reimbursement.moveIn(deposit, to: dinner, in: context)

        #expect(walletBalance(store.checking, asOf: today) == Money(cents: -35_00))
    }

    @Test func restoringTheDepositUndoesTheMoveSoItCountsOnce() throws {
        let dinner = try store.dinner()
        let deposit = try deposit()
        let kept = try context.payBack(10_00, on: day(2026, 10, 4), to: dinner)
        try Reimbursement.moveIn(deposit, to: dinner, in: context, at: deletedAt)

        try deposit.restore()

        #expect(!deposit.isInRecentlyDeleted)
        #expect(dinner.orderedReimbursements == [kept])
        #expect(dinner.netCents == -50_00)
        #expect(walletBalance(store.checking, asOf: store.today) == Money(cents: -25_00))
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 1)
    }

    @Test func restoringTheDepositUndoesTheMoveEvenAfterTheEntryWasEdited() throws {
        let dinner = try store.dinner()
        let deposit = try deposit()
        let entry = try Reimbursement.moveIn(deposit, to: dinner, in: context, at: deletedAt)
        try entry.update(with: ReimbursementDraft(amount: Money(cents: 30_00), day: day(2026, 10, 6)))

        try deposit.restore()

        #expect(dinner.orderedReimbursements.isEmpty)
        #expect(dinner.netCents == -60_00)
    }

    @Test func restoringTheDepositOfAnExpenseInRecentlyDeletedTakesItsEntryOffToo() throws {
        let dinner = try store.dinner()
        let deposit = try deposit()
        try Reimbursement.moveIn(deposit, to: dinner, in: context, at: deletedAt)
        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        try deposit.restore()
        try dinner.restore()

        #expect(dinner.orderedReimbursements.isEmpty)
        #expect(walletBalance(store.checking, asOf: store.today) == Money(cents: -35_00))
    }

    @Test func removingTheMovedDepositForGoodKeepsItsEntry() throws {
        let dinner = try store.dinner()
        let deposit = try deposit()
        try Reimbursement.moveIn(deposit, to: dinner, in: context, at: deletedAt)

        try deposit.deleteForever(in: context)

        #expect(dinner.orderedReimbursements.map(\.amountCents) == [25_00])
        #expect(dinner.netCents == -35_00)
    }

    @Test func aDepositCanBeMovedInAfterOtherEntries() throws {
        let dinner = try store.dinner()
        try context.payBack(20_00, on: day(2026, 10, 4), to: dinner)

        try Reimbursement.moveIn(try deposit(10_00), to: dinner, in: context)

        #expect(dinner.orderedReimbursements.map(\.amountCents) == [20_00, 10_00])
        #expect(dinner.netCents == -30_00)
    }

    @Test func aDepositAboveTheExpenseMovesInAsAnOverReimbursement() throws {
        let dinner = try store.dinner()

        try Reimbursement.moveIn(try deposit(100_00), to: dinner, in: context)

        #expect(dinner.netCents == 40_00)
    }

    // MARK: What can't move in

    @Test func onlyMoneyThatCameInUnderAnIncomeCategoryCanMoveIn() throws {
        let dinner = try store.dinner()
        let salary = try deposit()
        let expense = try store.record(-15_00, "Restaurants", on: day(2026, 10, 4))
        let adjustment = try deposit()
        adjustment.isBalanceAdjustment = true
        let incomingTransfer = try store.record(10_00, "Incoming transfer", .income, on: day(2026, 10, 5))
        let loan = try store.lendOrBorrow(.debt, 50_00, on: day(2026, 10, 5))
        let deleted = try deposit()
        try deleted.delete(.onlySelected, in: context, at: deletedAt)

        #expect(salary.canBeMovedIntoReimbursement(of: dinner))
        #expect(!expense.canBeMovedIntoReimbursement(of: dinner))
        #expect(!adjustment.canBeMovedIntoReimbursement(of: dinner))
        #expect(!incomingTransfer.canBeMovedIntoReimbursement(of: dinner))
        #expect(!loan.canBeMovedIntoReimbursement(of: dinner))
        #expect(!deleted.canBeMovedIntoReimbursement(of: dinner))
    }

    @Test func aDepositInAnotherWalletCantMoveInAndNothingChanges() throws {
        let dinner = try store.dinner()
        let savings = context.addWallet("Savings")
        let elsewhere = try store.record(25_00, "Tips", .income, on: day(2026, 10, 5), in: savings)

        #expect(!elsewhere.canBeMovedIntoReimbursement(of: dinner))
        #expect(throws: ReimbursementRuleError.otherWallet) {
            try Reimbursement.moveIn(elsewhere, to: dinner, in: context)
        }
        #expect(dinner.orderedReimbursements.isEmpty)
        #expect(!elsewhere.isInRecentlyDeleted)
    }

    @Test func whatAnOverpaidLoanBringsInCantMoveIn() throws {
        let dinner = try store.dinner()
        let loan = try store.lendOrBorrow(.loan, 100_00, on: day(2026, 10, 1))
        let overpaid = try #require(try context.pay(120_00, on: loan, on: day(2026, 10, 5)).overpayment)
        #expect(overpaid.category?.type == .income)

        #expect(!overpaid.canBeMovedIntoReimbursement(of: dinner))
        #expect(throws: ReimbursementRuleError.notADeposit) {
            try Reimbursement.moveIn(overpaid, to: dinner, in: context)
        }
        #expect(!overpaid.isInRecentlyDeleted)
    }

    @Test func aTransactionThatIsntADepositIsRefusedAndNothingChanges() throws {
        let dinner = try store.dinner()
        let lunch = try store.record(-15_00, "Restaurants", on: day(2026, 10, 4))

        #expect(throws: ReimbursementRuleError.notADeposit) {
            try Reimbursement.moveIn(lunch, to: dinner, in: context)
        }

        #expect(dinner.orderedReimbursements.isEmpty)
        #expect(!lunch.isInRecentlyDeleted)
    }

    @Test func movingIntoATransactionThatIsntAnExpenseIsRefusedAndTheDepositStays() throws {
        let otherDeposit = try deposit()
        let deposit = try deposit()

        #expect(throws: ReimbursementRuleError.notAnExpense) {
            try Reimbursement.moveIn(deposit, to: otherDeposit, in: context)
        }

        #expect(!deposit.isInRecentlyDeleted)
        #expect(otherDeposit.orderedReimbursements.isEmpty)
    }

    // MARK: The row's list of entries

    @Test func anExpenseWithoutReimbursementsHasNoSummary() throws {
        #expect(try store.dinner().reimbursementSummary(locale: unitedStates) == "")
    }

    @Test func theSummaryListsEntriesEarliestFirstAndDropsWholeCents() throws {
        let dinner = try store.dinner()
        try context.payBack(10_00, on: day(2026, 10, 6), to: dinner)
        try context.payBack(20_00, on: day(2026, 10, 4), to: dinner)
        try context.payBack(3_50, on: day(2026, 10, 9), to: dinner)

        #expect(dinner.reimbursementSummary(locale: unitedStates) == "+20, +10, +3.50")
    }
}
