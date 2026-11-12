import Foundation
import SwiftData
import Testing
@testable import Grosh

/// What a link joins is stored with it (ADR-0012): the rule that makes each link gives it its kind, every role check
/// reads it, and a store from before is brought up to date when it opens.
@MainActor
@Suite(.namedInTheLog)
struct LinkKindTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.checking }
    private var cash: Wallet { fixture.cash }
    private var today: CalendarDay { fixture.today }

    init() throws {
        fixture = try ExpectationFixture()
    }

    /// A $60 dinner in Checking and $20 of it paid back into Cash, with no one expected to pay.
    private func paidBackIntoCash() throws -> (dinner: Transaction, payback: Transaction) {
        let dinner = try fixture.dinner()
        return (dinner, try context.payBack(20_00, on: today, to: dinner, into: cash))
    }

    // MARK: Made by the rule that links

    @Test func aTransfersHalvesAreOnATransferLink() throws {
        var draft = TransferDraft(day: today)
        draft.from = checking
        draft.to = cash
        draft.amount = Money(cents: 50_00)

        let transfer = try Transfer.create(draft, in: context)

        #expect(transfer.outgoing.linkKind == .transfer)
        #expect(transfer.incoming.linkKind == .transfer)
        #expect(transfer.outgoing.linkID == transfer.incoming.linkID)
    }

    @Test func aLoanItsPaymentsAndWhatItWritesOffAreOnTheLoansLink() throws {
        let loan = try fixture.store.lendOrBorrow(.loan, 100_00, on: today)

        let recorded = try context.pay(120_00, on: loan, on: today)
        let overpayment = try #require(recorded.overpayment)

        #expect([loan, recorded.payment, overpayment].allSatisfy { $0.linkKind == .loanOrDebt })
        #expect(overpayment.isDebtWriteOff)
        #expect(!overpayment.isSplitPart)
        #expect(recorded.payment.paidLoanOrDebtKind == .loan)
        #expect(loan.paidLoanOrDebtKind == nil)
    }

    @Test func anExpenseAndItsPaybackAreOnAPaybackLink() throws {
        let (dinner, payback) = try paidBackIntoCash()

        #expect(dinner.linkKind == .payback)
        #expect(payback.linkKind == .payback)
        #expect(!dinner.isSplitPart)
        #expect(dinner.editFlow == .addSheet)
    }

    @Test func undoSplitTakesTheOriginalOffTheLink() throws {
        let dinner = try fixture.dinner()
        var draft = SplitDraft(splitting: dinner)
        var part = draft.newPart()
        part.amount = Money(cents: 10_00)
        draft.addPart(part)
        let parts = try dinner.split(draft)

        #expect(([dinner] + parts).allSatisfy { $0.linkKind == .split })

        let original = try parts[0].undoSplit()

        #expect(original === dinner)
        #expect(dinner.linkKind == nil)
        #expect(dinner.linkID == nil)
    }

    // MARK: Worked out for a link made before

    @Test func aLinksKindIsWorkedOutFromItsTransactions() throws {
        func kind(of roles: LockedRole?...) throws -> LinkKind {
            let members = try roles.map { role in
                Transaction.insert(
                    cents: -1_00, on: today, wallet: checking,
                    category: try role.map(context.lockedCategory) ?? fixture.store.category("Restaurants"), in: context
                )
            }
            return LinkKind(of: members)
        }

        #expect(try kind(of: .outgoingTransfer, .incomingTransfer) == .transfer)
        #expect(try kind(of: .loan, .debtCollection, nil) == .loanOrDebt)
        #expect(try kind(of: .repayment) == .loanOrDebt)
        #expect(try kind(of: nil, .reimbursement) == .payback)
        #expect(try kind(of: nil, nil) == .split)
    }

    @Test func anExpenseMarkedPaidBackWithNoPaybacksLeftIsNoLongerMarkedWhenTheStoreOpens() throws {
        let (dinner, payback) = try paidBackIntoCash()
        // As an older version left it: the payback gone for good, the Expense still marked and linked.
        payback.paidBackExpense = nil
        try context.save()

        try Transaction.migrateLinkKinds(in: context)

        #expect(!dinner.hasPaybacksElsewhere)
        #expect(dinner.linkKind == nil)
        #expect(dinner.canBeSplit)
    }

    // MARK: Paybacks removed for good

    @Test func anExpenseWhoseLastPaybackIsRemovedForGoodCanBeSplitAndMovedAgain() throws {
        let (dinner, payback) = try paidBackIntoCash()
        try payback.delete(.onlySelected, in: context)

        // Waiting in Recently Deleted, the payback still holds the Expense in its wallet.
        #expect(dinner.hasPaybacksElsewhere)
        #expect(!dinner.canBeSplit)

        try payback.deleteForever()

        #expect(!dinner.hasPaybacksElsewhere)
        #expect(dinner.linkID == nil)
        #expect(dinner.canBeSplit)
        var moved = TransactionDraft(editing: dinner)
        moved.wallet = cash
        try dinner.update(with: moved)
        #expect(dinner.wallet === cash)
    }

    @Test func anExpenseKeepsItsMarkWhileAnotherPaybackIsLeft() throws {
        let (dinner, first) = try paidBackIntoCash()
        let second = try context.payBack(5_00, on: today, to: dinner, into: cash)
        try first.delete(.onlySelected, in: context)

        try first.deleteForever()

        #expect(dinner.hasPaybacksElsewhere)
        #expect(dinner.linkID == second.linkID)
        #expect(!dinner.canBeSplit)
    }

    // MARK: Owes me and Reimbursements agree

    @Test func whatTheAddSheetOffersOwesMeOnCanBePaidBackOnceSaved() throws {
        var expense = TransactionDraft(type: .expense, day: today)
        expense.wallet = checking
        expense.amount = Money(cents: 30_00)
        expense.category = try fixture.store.category("Restaurants")
        var income = TransactionDraft(type: .income, day: today)
        income.wallet = checking
        income.amount = Money(cents: 30_00)
        income.category = try fixture.store.otherIncome()

        #expect(expense.offersOwesMe)
        #expect(try Transaction.create(expense, in: context).canBeReimbursed)
        #expect(!income.offersOwesMe)
        #expect(!(try Transaction.create(income, in: context).canBeReimbursed))
    }

    @Test func moneyMissingFromABalanceAdjustmentIsNeitherPaidBackNorOwed() throws {
        var draft = try BalanceAdjustmentDraft(wallet: checking, day: today, in: context)
        draft.realBalance = Money(cents: -15_00)

        let adjustment = try Transaction.adjustBalance(draft, in: context)

        #expect(adjustment.category?.type == .expense)
        #expect(!adjustment.canBeReimbursed)
    }
}

/// A Person's name changes only by renaming, which every With they are in follows (ADR-0009).
@MainActor
@Suite(.namedInTheLog)
struct PersonRenameTests {
    @Test func renamingAPersonRenamesEveryWithTheyAreIn() throws {
        let fixture = try ExpectationFixture()
        let anna = try fixture.person("Anna")
        let ivan = try fixture.person("Ivan")
        let dinner = try fixture.dinner()
        dinner.setPeople([anna, ivan])

        anna.rename(to: "Zoe")

        #expect(dinner.withName == "Ivan; Zoe")
    }
}
