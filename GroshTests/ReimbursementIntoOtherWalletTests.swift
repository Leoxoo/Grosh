import Foundation
import SwiftData
import Testing
@testable import Grosh

/// A payback recorded into a different wallet than the Expense's (ADR-0010): a real transaction there, dated the day it
/// was received, under the locked Reimbursement category, linked to the Expense like the halves of a transfer. It counts
/// in its own wallet, is hidden from the Total list, and the Expense shows its net in the Total while its own wallet keeps
/// the full amount.
@MainActor
struct ReimbursementIntoOtherWalletTests {
    private let fixture: ExpectationFixture
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.checking }
    private var cash: Wallet { fixture.cash }
    private var today: CalendarDay { fixture.today }
    private let receivedDay = day(2026, 10, 8)
    private let deletedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        fixture = try ExpectationFixture()
    }

    /// A $60 dinner on the 3rd in Checking that Alex owes $30 of, and the $20 he paid into Cash on the 8th.
    @discardableResult
    private func paidBackIntoCash(
        _ cents: Int = 20_00
    ) throws -> (dinner: Transaction, owed: ExpectedReimbursement, payback: Transaction) {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        let recorded = try fixture.pay(cents, on: owed, day: receivedDay, into: cash, note: "Cash")
        guard case .inOtherWallet(let payback) = recorded else {
            Issue.record("Expected a transaction in the other wallet.")
            throw PaybackTestError.notElsewhere
        }
        return (dinner, owed, payback)
    }

    private enum PaybackTestError: Error { case notElsewhere }

    private var monthDays: DayRange { Period.month(CalendarMonth(today)).days(today: today) }

    /// What the Transactions tab lists for `selection` in October.
    private func listed(in selection: WalletSelection) throws -> [Transaction] {
        let all = try context.fetch(Transaction.notDeleted)
        return TransactionFilter().listed(from: all, selection: selection, on: monthDays)
    }

    // MARK: Recording it

    @Test func choosingTheExpensesWalletBehavesAsBefore() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)

        let recorded = try fixture.pay(10_00, on: owed, into: checking)

        guard case .onExpense = recorded else {
            Issue.record("Expected a Reimbursement on the Expense.")
            return
        }
        #expect(dinner.reimbursedCents == 10_00)
        #expect(!dinner.hasPaybacksElsewhere)
        #expect(dinner.linkID == nil)
    }

    @Test func anotherWalletMakesALinkedTransactionThereUnderTheLockedReimbursementCategory() throws {
        let (dinner, owed, payback) = try paidBackIntoCash()

        #expect(payback.wallet === cash)
        #expect(payback.amountCents == 20_00)
        #expect(payback.day == receivedDay)
        #expect(payback.note == "Cash")
        #expect(payback.category?.lockedRole == .reimbursement)
        #expect(payback.category?.isLocked == true)
        #expect(payback.category?.type == .income)
        #expect(payback.orderedPeople.map(\.name) == ["Alex"])
        #expect(payback.paidExpectation === owed)
        #expect(payback.linkID != nil)
        #expect(payback.linkID == dinner.linkID)
        #expect(dinner.hasPaybacksElsewhere)
        #expect(dinner.reimbursedCents == 0)
        #expect(try payback.related(in: context) == [dinner])
        #expect(try dinner.related(in: context) == [payback])
    }

    @Test func thePaybackCountsInTheExpectation() throws {
        let (_, owed, payback) = try paidBackIntoCash()

        #expect(owed.paid == Money(cents: 20_00))
        #expect(owed.outstanding == Money(cents: 10_00))
        #expect(owed.isOpen)
        let payments = owed.payments
        #expect(payments.count == 1)
        #expect(payments.first?.isElsewhere == true)
        #expect(payments.first?.wallet === cash)
        #expect(payments.first?.id == payback.persistentModelID)

        try fixture.pay(10_00, on: owed, into: cash)
        #expect(owed.status == .paidBack)
    }

    /// Cents of one currency are never counted as another's: money that came into a wallet in another currency than the
    /// Expense's can't be recorded against it, and nothing is made.
    @Test func aWalletInAnotherCurrencyIsRefused() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        let owed = try fixture.expectation(of: alex, on: dinner)
        let euros = Wallet(name: "Euros")
        euros.currencyCode = "EUR"
        context.insert(euros)

        #expect(throws: ExpectedReimbursementRuleError.otherCurrency) {
            try fixture.pay(20_00, on: owed, into: euros)
        }
        #expect(owed.paid == Money(cents: 0))
        #expect(!dinner.hasPaybacksElsewhere)
        #expect(euros.transactions?.isEmpty ?? true)
    }

    // MARK: Balances

    @Test func thePaybackCountsInItsWalletAndTheExpenseKeepsItsFullAmountInItsOwn() throws {
        let (dinner, _, _) = try paidBackIntoCash()

        #expect(checking.balance(asOf: today) == Money(cents: -60_00))
        #expect(cash.balance(asOf: today) == Money(cents: 20_00))
        #expect(Wallet.total(of: [checking, cash], asOf: today) == Money(cents: -40_00))
        #expect(dinner.netCents == -60_00)
        let entries = try context.fetch(Transaction.notDeleted).map(LedgerEntry.init)
        let balances = WalletBalances(entries, asOf: today)
        #expect(balances.balance(of: cash) == Money(cents: 20_00))
        #expect(balances.total(of: [checking, cash]) == Money(cents: -40_00))
    }

    // MARK: Lists

    @Test func theTotalListHidesThePaybackAndItsWalletListShowsIt() throws {
        let (dinner, _, payback) = try paidBackIntoCash()

        #expect(try listed(in: .total) == [dinner])
        #expect(try listed(in: .wallet(cash)) == [payback])
        #expect(try listed(in: .wallet(checking)) == [dinner])
        #expect(payback.isHiddenInTotal)
        #expect(!dinner.isHiddenInTotal)
    }

    @Test func searchStillFindsThePayback() throws {
        let (_, _, payback) = try paidBackIntoCash()
        let all = try context.fetch(Transaction.notDeleted)

        let found = TransactionFilter(searchText: "Alex").listed(from: all, selection: .total, on: monthDays)

        #expect(found.contains(payback))
    }

    @Test func theExpenseShowsItsNetInTheTotalAndTheFullAmountInItsOwnWallet() throws {
        let (dinner, _, _) = try paidBackIntoCash()

        #expect(dinner.totalViewNetCents == -40_00)
        #expect([dinner].total(.netInTotal) == Money(cents: -40_00))
        #expect([dinner].total(.net) == Money(cents: -60_00))
        #expect(TransactionDay.days(of: [dinner]).first?.total(.netInTotal) == Money(cents: -40_00))
        #expect(TransactionDay.days(of: [dinner]).first?.total(.net) == Money(cents: -60_00))
        #expect(TransactionCategoryGroup.groups(of: [dinner], listed: .netInTotal).first?.total == Money(cents: -40_00))
    }

    @Test func theExpensesOwnWalletNotesWhatWasReimbursedToWhichWallet() throws {
        let (dinner, _, _) = try paidBackIntoCash()
        let locale = Locale(identifier: "en_US")

        #expect(dinner.elsewhereSummary(locale: locale) == "+20 to Cash")
        #expect(dinner.paybacksElsewhere.map(\.wallet?.name) == ["Cash"])
    }

    @Test func aPaybackIntoAWalletLeftOutOfTheTotalIsNotCountedInTheExpensesTotalNet() throws {
        cash.includeInTotal = false
        let (dinner, _, _) = try paidBackIntoCash()

        #expect(dinner.totalViewNetCents == -60_00)
        #expect(Wallet.total(of: [checking, cash], asOf: today) == Money(cents: -60_00))
        #expect(try listed(in: .total) == [dinner])
        #expect(try fixture.totals(in: .total).spent == Money(cents: 60_00))
        #expect(try listed(in: .wallet(cash)).count == 1)
    }

    @Test func aPaybackWhoseExpenseIsOutsideTheTotalStaysInIt() throws {
        checking.includeInTotal = false
        let (_, _, payback) = try paidBackIntoCash()

        #expect(!payback.isHiddenInTotal)
        #expect(try listed(in: .total) == [payback])
        #expect(Wallet.total(of: [checking, cash], asOf: today) == Money(cents: 20_00))
    }

    // MARK: Reports

    @Test func theTotalReportCountsTheExpenseNetOfPaybacksAndNothingForThePayback() throws {
        try paidBackIntoCash()

        #expect(try fixture.totals(in: .total) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 40_00)))
        #expect(try fixture.store.graph(.spent).headline == Money(cents: 40_00))
        #expect(try fixture.store.graph(.income).headline == Money(cents: 0))
    }

    @Test func aSingleWalletsReportCountsOnlyWhatHappenedInIt() throws {
        let (_, _, payback) = try paidBackIntoCash()
        let otherIncome = try fixture.store.otherIncome()

        #expect(try fixture.totals(in: .wallet(checking)) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 60_00)))
        #expect(try fixture.totals(in: .wallet(cash)) == PeriodTotals(income: Money(cents: 20_00), spent: Money(cents: 0)))
        let counted = try #require(payback.countedAmount(in: .wallet(cash), otherIncome: otherIncome))
        #expect(counted.side == .income)
        #expect(counted.category.lockedRole == .reimbursement)
        #expect(payback.countedAmount(in: .total, otherIncome: otherIncome) == nil)
    }

    @Test func paybacksBeyondTheExpenseCountTheExtraAsOtherIncomeInTheTotal() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(40_00, owing: [(alex, 30_00)])
        try fixture.pay(50_00, on: fixture.expectation(of: alex, on: dinner), day: receivedDay, into: cash)

        let counted = try #require(dinner.countedAmount(otherIncome: fixture.store.otherIncome()))

        #expect(counted.side == .income)
        #expect(counted.amount == Money(cents: 10_00))
        #expect(counted.category.name == "Other Income")
    }

    // MARK: Linked transactions

    @Test func deletingTheExpenseOffersToDeleteThePaybackToo() throws {
        let (dinner, _, payback) = try paidBackIntoCash()

        #expect(try dinner.deleteScopes(in: context) == [.withRelated, .onlySelected])
        try dinner.delete(.withRelated, in: context, at: deletedAt)

        #expect(dinner.isInRecentlyDeleted)
        #expect(payback.isInRecentlyDeleted)
        #expect(checking.balance(asOf: today) == Money(cents: 0))
        #expect(cash.balance(asOf: today) == Money(cents: 0))
        #expect(try fixture.totals(in: .total) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
        #expect(try listed(in: .total).isEmpty)
    }

    @Test func restoringBringsBackBothTheExpenseAndThePayback() throws {
        let (dinner, owed, payback) = try paidBackIntoCash()
        try dinner.delete(.withRelated, in: context, at: deletedAt)

        try dinner.restore()
        try payback.restore()

        #expect(!dinner.isInRecentlyDeleted)
        #expect(!payback.isInRecentlyDeleted)
        #expect(checking.balance(asOf: today) == Money(cents: -60_00))
        #expect(cash.balance(asOf: today) == Money(cents: 20_00))
        #expect(dinner.totalViewNetCents == -40_00)
        #expect(owed.paid == Money(cents: 20_00))
        #expect(try listed(in: .total) == [dinner])
    }

    @Test func deletingOnlyThePaybackLeavesTheExpenseAtItsFullAmountUntilItIsRestored() throws {
        let (dinner, owed, payback) = try paidBackIntoCash()

        try payback.delete(.onlySelected, in: context, at: deletedAt)

        #expect(dinner.totalViewNetCents == -60_00)
        #expect(cash.balance(asOf: today) == Money(cents: 0))
        #expect(owed.paid == Money(cents: 0))
        #expect(owed.isOpen)
        #expect(try fixture.totals(in: .total).spent == Money(cents: 60_00))

        try payback.restore()

        #expect(dinner.totalViewNetCents == -40_00)
        #expect(cash.balance(asOf: today) == Money(cents: 20_00))
        #expect(owed.paid == Money(cents: 20_00))
    }

    @Test func aPaybackWhoseExpenseIsDeletedOnItsOwnStaysInTheTotalAsMoneyIn() throws {
        let (dinner, _, payback) = try paidBackIntoCash()

        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        #expect(!payback.isHiddenInTotal)
        #expect(try listed(in: .total) == [payback])
    }

    @Test func theExpenseStaysEditableAndThePaybackIsOwnedByRecordPayment() throws {
        let (dinner, _, payback) = try paidBackIntoCash()

        #expect(dinner.editFlow == .addSheet)
        #expect(!dinner.isSplitPart)
        #expect(!dinner.canBeSplit)
        #expect(payback.editFlow == nil)
        #expect(!payback.isSplitPart)
        #expect(!payback.canBeSplit)
        #expect(!payback.canBeDuplicated)
    }

    @Test func theExpenseCanBeEditedButStaysInItsWallet() throws {
        let (dinner, _, _) = try paidBackIntoCash()

        var note = TransactionDraft(editing: dinner)
        note.note = "Birthday dinner"
        try dinner.update(with: note)
        #expect(dinner.note == "Birthday dinner")

        var moved = TransactionDraft(editing: dinner)
        moved.wallet = cash
        #expect(throws: ExpectedReimbursementRuleError.walletLockedByPaybacks) {
            try dinner.update(with: moved)
        }
        #expect(dinner.wallet === checking)
    }

    @Test func aPartOfASplitCantBePaidBackIntoAnotherWallet() throws {
        let alex = try fixture.person("Alex")
        let dinner = try fixture.dinner(owing: [(alex, 30_00)])
        dinner.linkID = UUID()
        let owed = try fixture.expectation(of: alex, on: dinner)

        #expect(throws: ExpectedReimbursementRuleError.splitPart) {
            try fixture.pay(10_00, on: owed, into: cash)
        }
        #expect(!dinner.hasPaybacksElsewhere)
    }

    // MARK: Without Owes me

    /// Someone paid me back, into another wallet, on an Expense nobody was expected to pay back: the same linked
    /// transaction there as Record payment makes, with no one in With and no expectation.
    @Test func someonePaidMeBackIntoAnotherWalletWithoutOwesMe() throws {
        let dinner = try fixture.dinner()
        let draft = ReimbursementDraft(amount: Money(cents: 20_00), day: receivedDay, note: "Cash")

        let payback = try dinner.recordPaybackElsewhere(draft, into: cash, in: context)

        #expect(payback.wallet === cash)
        #expect(payback.amountCents == 20_00)
        #expect(payback.day == receivedDay)
        #expect(payback.category?.lockedRole == .reimbursement)
        #expect(payback.paidBackExpense === dinner)
        #expect(payback.paidExpectation == nil)
        #expect(payback.orderedPeople.isEmpty)
        #expect(dinner.paybacksElsewhere == [payback])
        #expect(dinner.reimbursedCents == 0)
        #expect(try payback.related(in: context) == [dinner])
        #expect(try listed(in: .total) == [dinner])
        #expect(dinner.totalViewNetCents == -40_00)
        #expect(cash.balance(asOf: today) == Money(cents: 20_00))
    }

    @Test func someonePaidMeBackIntoAWalletInAnotherCurrencyIsRefused() throws {
        let dinner = try fixture.dinner()
        let euros = Wallet(name: "Euros")
        euros.currencyCode = "EUR"
        context.insert(euros)
        let draft = ReimbursementDraft(amount: Money(cents: 20_00), day: receivedDay)

        #expect(throws: ExpectedReimbursementRuleError.otherCurrency) {
            try dinner.recordPaybackElsewhere(draft, into: euros, in: context)
        }
        #expect(!dinner.hasPaybacksElsewhere)
    }

    // MARK: The category

    @Test func theReimbursementCategoryIsLockedAndOnlyFiledByRecordPayment() throws {
        let category = try context.lockedCategory(.reimbursement)

        #expect(category.name == "Reimbursement")
        #expect(category.type == .income)
        #expect(category.isLocked)
        #expect(!LockedRole.reimbursement.isOfferedInPicker)
        #expect(!category.isTransferHalf)
    }
}
