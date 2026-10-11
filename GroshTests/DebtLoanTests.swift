import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Settling Loans and Debts (ADR-0003, ADR-0004): Outstanding, Record payment, overpayment and Forgive the rest.
@MainActor
struct DebtLoanTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.wallet }
    private let lentOn = CalendarDay(year: 2026, month: 5, day: 27)
    private let paidOn = CalendarDay(year: 2026, month: 6, day: 15)

    init() throws {
        store = try CategoryFixture()
    }

    /// A Loan (you lent) or Debt (you borrowed) of `cents` with `name`, saved through the Add sheet's draft.
    private func record(_ role: LockedRole, _ cents: Int, with name: String) throws -> Transaction {
        var draft = TransactionDraft(type: .debtLoan, day: lentOn)
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try context.lockedCategory(role)
        draft.withName = name
        return try Transaction.create(draft, in: context)
    }

    private func lend(_ cents: Int, to name: String = "Pasha") throws -> Transaction {
        try record(.loan, cents, with: name)
    }

    private func borrow(_ cents: Int, from name: String = "Anna") throws -> Transaction {
        try record(.debt, cents, with: name)
    }

    /// Records a payment of `cents` against `loanOrDebt` on `day` through Record payment's draft.
    @discardableResult
    private func pay(_ cents: Int, on loanOrDebt: Transaction, day: CalendarDay? = nil) throws -> DebtPayment {
        var draft = try DebtPaymentDraft(settling: loanOrDebt, on: day ?? paidOn, in: context)
        draft.amount = Money(cents: cents)
        return try DebtPayment.record(draft, in: context)
    }

    /// What is still outstanding on `original`, a Loan or Debt, as every screen works it out.
    private func outstanding(_ original: Transaction) throws -> Money {
        try #require(try LoanOrDebt(original, in: context)).outstanding
    }

    private func isSettled(_ original: Transaction) throws -> Bool {
        try #require(try LoanOrDebt(original, in: context)).isSettled
    }

    // MARK: Outstanding

    @Test func aLoanWithNoPaymentsIsOutstandingInFull() throws {
        let loan = try lend(100_00)

        #expect(try outstanding(loan) == Money(cents: 100_00))
        #expect(try !isSettled(loan))
    }

    // MARK: Record payment

    @Test func aPartialPaymentLeavesTheRestOutstanding() throws {
        let loan = try lend(100_00)

        try pay(60_00, on: loan)

        #expect(try outstanding(loan) == Money(cents: 40_00))
        #expect(try !isSettled(loan))
    }

    @Test func aPaymentOnALoanIsALinkedDebtCollectionExcludedFromReport() throws {
        let loan = try lend(100_00)

        let recorded = try pay(60_00, on: loan)

        let collection = recorded.payment
        #expect(collection.category == (try context.lockedCategory(.debtCollection)))
        #expect(collection.amountCents == 60_00)
        #expect(collection.day == paidOn)
        #expect(collection.wallet == checking)
        #expect(collection.withName == "Pasha")
        #expect(collection.isExcludedFromReport)
        #expect(recorded.overpayment == nil)
        #expect(try loan.related(in: context) == [collection])
        #expect(checking.balance(asOf: paidOn) == Money(cents: -40_00))
    }

    @Test func aPaymentOnADebtIsALinkedRepaymentTakenFromTheWallet() throws {
        let debt = try borrow(100_00)

        let repayment = try pay(25_00, on: debt).payment

        #expect(repayment.category == (try context.lockedCategory(.repayment)))
        #expect(repayment.amountCents == -25_00)
        #expect(repayment.withName == "Anna")
        #expect(repayment.isExcludedFromReport)
        #expect(try debt.related(in: context) == [repayment])
        #expect(try outstanding(debt) == Money(cents: 75_00))
        #expect(checking.balance(asOf: paidOn) == Money(cents: 75_00))
    }

    @Test func recordPaymentStartsAtWhatIsOutstanding() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)

        let draft = try DebtPaymentDraft(settling: loan, on: paidOn, in: context)

        #expect(draft.amount == Money(cents: 40_00))
        #expect(draft.day == paidOn)
    }

    // MARK: Overpayment

    /// The ticket's example: a $100 Loan, $60 paid leaves $40; then $70 paid settles it, and $30 is income.
    @Test func paymentsAboveWhatIsOutstandingSettleTheLoanAndTheRestIsIncome() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)
        #expect(try outstanding(loan) == Money(cents: 40_00))

        var draft = try DebtPaymentDraft(settling: loan, on: paidOn.adding(days: 7), in: context)
        draft.amount = Money(cents: 70_00)
        draft.overpaymentCategory = try store.category("Collect Interest", .income)
        #expect(draft.overpaid == Money(cents: 30_00))
        let recorded = try DebtPayment.record(draft, in: context)

        #expect(recorded.payment.amountCents == 40_00)
        #expect(recorded.payment.isExcludedFromReport)
        let income = try #require(recorded.overpayment)
        #expect(income.amountCents == 30_00)
        #expect(income.category == (try store.category("Collect Interest", .income)))
        #expect(income.countsInReport)
        #expect(income.day == paidOn.adding(days: 7))
        #expect(income.withName == "Pasha")
        #expect(try loan.related(in: context).contains(income))
        #expect(try outstanding(loan) == Money(cents: 0))
        #expect(try isSettled(loan))
        #expect(checking.balance(asOf: paidOn.adding(days: 7)) == Money(cents: 30_00))
    }

    @Test func anOverpaidDebtIsAnExpenseForTheRest() throws {
        let debt = try borrow(100_00)

        var draft = try DebtPaymentDraft(settling: debt, on: paidOn, in: context)
        draft.amount = Money(cents: 120_00)
        draft.overpaymentCategory = try store.category("Gifts & Donations")
        let recorded = try DebtPayment.record(draft, in: context)

        #expect(recorded.payment.amountCents == -100_00)
        let expense = try #require(recorded.overpayment)
        #expect(expense.amountCents == -20_00)
        #expect(expense.category == (try store.category("Gifts & Donations")))
        #expect(expense.countsInReport)
        #expect(try isSettled(debt))
    }

    @Test(arguments: [(LockedRole.loan, LockedRole.otherIncome), (.debt, .otherExpense)])
    func anOverpaymentIsOtherIncomeOrOtherExpenseUnlessAnotherCategoryIsPicked(
        role: LockedRole, expected: LockedRole
    ) throws {
        let original = try record(role, 100_00, with: "Pasha")

        let draft = try DebtPaymentDraft(settling: original, on: paidOn, in: context)

        #expect(draft.overpaymentCategory == (try context.lockedCategory(expected)))
        #expect(draft.overpaymentType == (role == .loan ? .income : .expense))
    }

    @Test func nothingIsOverpaidUpToWhatIsOutstanding() throws {
        let loan = try lend(100_00)

        var draft = try DebtPaymentDraft(settling: loan, on: paidOn, in: context)
        draft.amount = Money(cents: 100_00)

        #expect(draft.overpaid == Money(cents: 0))
        #expect(try DebtPayment.record(draft, in: context).overpayment == nil)
    }

    // MARK: Payment rules

    private func transactionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Transaction>())
    }

    @Test func aPaymentOfNothingIsRefused() throws {
        let loan = try lend(100_00)
        var draft = try DebtPaymentDraft(settling: loan, on: paidOn, in: context)
        draft.amount = Money(cents: 0)

        #expect(!draft.canSave)
        #expect(throws: TransactionRuleError.missingAmount) { try DebtPayment.record(draft, in: context) }
        #expect(try transactionCount() == 1)
    }

    @Test func aSettledLoanTakesNoMorePayments() throws {
        let loan = try lend(100_00)
        let draft = try DebtPaymentDraft(settling: loan, on: paidOn, in: context)
        try DebtPayment.record(draft, in: context)

        #expect(throws: DebtLoanRuleError.alreadySettled) { try pay(10_00, on: loan) }
        #expect(throws: DebtLoanRuleError.alreadySettled) { try DebtPayment.record(draft, in: context) }
        #expect(try transactionCount() == 2)
    }

    @Test func anOverpaymentNeedsACategoryOfTheMatchingType() throws {
        let loan = try lend(100_00)
        var draft = try DebtPaymentDraft(settling: loan, on: paidOn, in: context)
        draft.amount = Money(cents: 120_00)

        draft.overpaymentCategory = try store.category("Café")
        #expect(!draft.canSave)
        #expect(throws: DebtLoanRuleError.categoryDoesNotMatch) { try DebtPayment.record(draft, in: context) }

        draft.overpaymentCategory = nil
        #expect(throws: TransactionRuleError.missingCategory) { try DebtPayment.record(draft, in: context) }
        #expect(try transactionCount() == 1)
    }

    // MARK: Forgive the rest

    @Test func forgivingALoanMarksItForgivenWithoutAddingAnyTransaction() throws {
        let loan = try lend(50_00)
        let collection = try pay(30_00, on: loan).payment
        let balanceBefore = checking.balance(asOf: paidOn)
        let countBefore = try transactionCount()
        let forgivenOn = paidOn.adding(days: 3)

        var draft = try ForgiveDraft(forgiving: loan, on: forgivenOn, in: context)
        draft.category = try store.category("Friends & Lover")
        draft.note = "  Birthday  "
        #expect(draft.forgiven == Money(cents: 20_00))
        let forgiveness = try Forgiveness.record(draft, in: context)

        #expect(try transactionCount() == countBefore)
        #expect(forgiveness.amount == Money(cents: 20_00))
        #expect(forgiveness.day == forgivenOn)
        #expect(forgiveness.category == (try store.category("Friends & Lover")))
        #expect(forgiveness.note == "Birthday")
        #expect(loan.isForgiven)
        #expect(try isSettled(loan))
        #expect(try outstanding(loan) == Money(cents: 0))
        #expect(try loan.related(in: context) == [collection])
        #expect(collection.amountCents == 30_00)
        #expect(checking.balance(asOf: forgivenOn) == balanceBefore)
    }

    @Test func forgivingADebtMarksItForgivenAndKeepsItsRepayments() throws {
        let debt = try borrow(250_00)
        try pay(200_00, on: debt)

        var draft = try ForgiveDraft(forgiving: debt, on: paidOn, in: context)
        draft.category = try store.category("Gifts", .income)
        try Forgiveness.record(draft, in: context)

        let settled = try #require(try LoanOrDebt(debt, in: context))
        #expect(settled.isSettled)
        #expect(settled.paid == Money(cents: 200_00))
        #expect(settled.forgiveness?.amount == Money(cents: 50_00))
        #expect(checking.balance(asOf: paidOn) == Money(cents: 50_00))
        #expect(try transactionCount() == 2)
    }

    @Test func theForgivenAmountCountsInReportsAsExpenseForALoanAndIncomeForADebt() throws {
        let loan = try lend(100_00)
        var forgiveLoan = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        forgiveLoan.category = try context.lockedCategory(.otherExpense)
        let forgivenLoan = try Forgiveness.record(forgiveLoan, in: context)
        let debt = try borrow(40_00)
        var forgiveDebt = try ForgiveDraft(forgiving: debt, on: paidOn, in: context)
        forgiveDebt.category = try context.lockedCategory(.otherIncome)
        let forgivenDebt = try Forgiveness.record(forgiveDebt, in: context)

        #expect(forgivenLoan.reportAmount == Money(cents: -100_00))
        #expect(forgivenLoan.category == (try context.lockedCategory(.otherExpense)))
        #expect(forgivenDebt.reportAmount == Money(cents: 40_00))
        #expect(forgivenDebt.day == paidOn)
    }

    @Test func unforgivingMakesWhatWasForgivenOutstandingAgain() throws {
        let loan = try lend(50_00)
        try pay(30_00, on: loan)
        var draft = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        draft.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(draft, in: context)

        try loan.unforgive()

        #expect(!loan.isForgiven)
        #expect(loan.forgiveness == nil)
        #expect(loan.forgivenCategory == nil)
        #expect(try outstanding(loan) == Money(cents: 20_00))
        #expect(throws: DebtLoanRuleError.notForgiven) { try loan.unforgive() }
        try pay(20_00, on: loan)
        #expect(try isSettled(loan))
    }

    @Test func deletingAPaymentOnAForgivenLoanMakesThatPartOutstandingAgain() throws {
        let loan = try lend(100_00)
        let collection = try pay(60_00, on: loan).payment
        var draft = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        draft.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(draft, in: context)

        try collection.delete(.onlySelected, in: context)

        #expect(try outstanding(loan) == Money(cents: 60_00))
        #expect(loan.forgiveness?.amount == Money(cents: 40_00))

        var again = try ForgiveDraft(forgiving: loan, on: paidOn.adding(days: 1), in: context)
        again.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(again, in: context)
        #expect(try isSettled(loan))
        #expect(loan.forgiveness?.amount == Money(cents: 100_00))
    }

    @Test(arguments: [(LockedRole.loan, LockedRole.otherExpense), (.debt, .otherIncome)])
    func whatIsForgivenIsOtherExpenseOrOtherIncomeUnlessAnotherCategoryIsPicked(
        role: LockedRole, expected: LockedRole
    ) throws {
        let original = try record(role, 100_00, with: "Pasha")

        let draft = try ForgiveDraft(forgiving: original, on: paidOn, in: context)

        #expect(draft.category == (try context.lockedCategory(expected)))
        #expect(draft.forgivenType == (role == .loan ? .expense : .income))
    }

    @Test func forgivingNeedsAnOpenLoanAndACategoryOfTheMatchingType() throws {
        let loan = try lend(100_00)
        var draft = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)

        draft.category = try store.category("Salary", .income)
        #expect(!draft.canSave)
        #expect(throws: DebtLoanRuleError.categoryDoesNotMatch) { try Forgiveness.record(draft, in: context) }

        draft.category = nil
        #expect(throws: TransactionRuleError.missingCategory) { try Forgiveness.record(draft, in: context) }
        #expect(!loan.isForgiven)

        try pay(100_00, on: loan)
        draft.category = try context.lockedCategory(.otherExpense)
        #expect(throws: DebtLoanRuleError.alreadySettled) { try Forgiveness.record(draft, in: context) }
        #expect(!loan.isForgiven)
    }

    @Test func aForgivenLoanTakesNoMorePaymentsUntilUnforgiven() throws {
        let loan = try lend(100_00)
        var forgive = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        forgive.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(forgive, in: context)

        #expect(throws: DebtLoanRuleError.alreadySettled) { try pay(10_00, on: loan) }
    }

    @Test func aForgivenLoanKeepsItsAmountWalletAndCategoryUntilUnforgiven() throws {
        let loan = try lend(100_00)
        var forgive = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        forgive.category = try context.lockedCategory(.otherExpense)
        try Forgiveness.record(forgive, in: context)
        let editing = TransactionDraft(editing: loan)
        #expect(editing.isLockedByPayments)

        var otherAmount = editing
        otherAmount.amount = Money(cents: 120_00)
        var otherCategory = editing
        otherCategory.category = try context.lockedCategory(.debt)
        #expect(throws: DebtLoanRuleError.lockedByForgiveness) { try loan.update(with: otherAmount) }
        #expect(throws: DebtLoanRuleError.lockedByForgiveness) { try loan.update(with: otherCategory) }

        var otherNote = editing
        otherNote.note = "Rent help"
        try loan.update(with: otherNote)
        #expect(loan.note == "Rent help")
        #expect(loan.isForgiven)
    }

    @Test func aCategoryAForgivenAmountCountsUnderCantBeDeletedAndMovesWhenMerged() throws {
        let loan = try lend(100_00)
        let friends = try store.category("Friends & Lover")
        var forgive = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        forgive.category = friends
        try Forgiveness.record(forgive, in: context)

        #expect(store.catalog.hasTransactions(friends))
        #expect(!store.catalog.canDelete(friends))

        let gifts = try store.category("Gifts & Donations")
        try store.catalog.merge(friends, into: gifts)
        #expect(loan.forgivenCategory == gifts)
    }

    @Test func theStoryAddsUpWhatWasLentPaidBackAndForgiven() {
        let story = LoanOrDebtKind.loan.story(
            owed: Money(cents: 50_00), paid: Money(cents: 30_00), forgiven: Money(cents: 20_00)
        )
        let debtStory = LoanOrDebtKind.debt.story(
            owed: Money(cents: 250_00), paid: Money(cents: 200_00), forgiven: Money(cents: 50_00)
        )

        func amount(_ cents: Int) -> String { Money(cents: cents).formatted() }
        #expect(story == "Lent \(amount(50_00)) · Collected \(amount(30_00)) · Forgiven \(amount(20_00))")
        #expect(debtStory == "Borrowed \(amount(250_00)) · Repaid \(amount(200_00)) · Forgiven \(amount(50_00)) · Kept \(amount(50_00))")
    }

    @Test func forgivenessRecordedUnderTheOldRuleStillSettlesTheLoan() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)
        // Before ADR-0004, forgiving added a Debt Collection of what was outstanding and an offsetting expense.
        let legacy = try LoanOrDebt(loan, in: context)
        let collection = try #require(legacy).addLinked(
            40_00, filedUnder: try context.lockedCategory(.debtCollection), on: paidOn, note: "",
            isExcludedFromReport: true, in: context
        )
        let expense = try #require(legacy).addLinked(
            -40_00, filedUnder: try context.lockedCategory(.otherExpense), on: paidOn, note: "",
            isExcludedFromReport: false, in: context
        )

        #expect(try isSettled(loan))
        #expect(!loan.isForgiven)
        #expect(collection.amountCents == 40_00)
        #expect(expense.cardRuleExemption == .debtWriteOff)
    }

    // MARK: The Card rule

    @Test func whatOverpayingADebtWritesOffNeedsNoCard() throws {
        try Card.create(CardDraft(name: "Apple Card", kind: .credit, payingWallet: checking), in: context)
        let debt = try borrow(100_00)
        var payment = try DebtPaymentDraft(settling: debt, on: paidOn, in: context)
        payment.amount = Money(cents: 120_00)
        let overpaid = try #require(try DebtPayment.record(payment, in: context).overpayment)
        let coffee = store.spend(4_50, on: try store.category("Café"))

        #expect(overpaid.card == nil)
        #expect(overpaid.cardRuleExemption == .debtWriteOff)
        #expect(!TransactionDraft(editing: overpaid).requiresCard)
        #expect(coffee.cardRuleExemption == nil)
        #expect(TransactionDraft(editing: coffee).requiresCard)
    }

    // MARK: The original never changes

    @Test func paymentsOverpaymentsAndForgivingNeverChangeTheOriginal() throws {
        var entered = TransactionDraft(type: .debtLoan, day: lentOn)
        entered.wallet = checking
        entered.amount = Money(cents: 100_00)
        entered.category = try context.lockedCategory(.loan)
        entered.withName = "Pasha"
        entered.note = "Rent help"
        entered.isExcludedFromReport = true
        let loan = try Transaction.create(entered, in: context)
        let enteredAt = loan.createdAt

        try pay(30_00, on: loan)
        var forgive = try ForgiveDraft(forgiving: loan, on: paidOn, in: context)
        forgive.category = try store.category("Friends & Lover")
        try Forgiveness.record(forgive, in: context)
        let debt = try borrow(50_00)
        try pay(80_00, on: debt)

        #expect(loan.amountCents == -100_00)
        #expect(loan.day == lentOn)
        #expect(loan.wallet == checking)
        #expect(loan.category == (try context.lockedCategory(.loan)))
        #expect(loan.note == "Rent help")
        #expect(loan.withName == "Pasha")
        #expect(loan.isExcludedFromReport)
        #expect(loan.createdAt == enteredAt)
        #expect(debt.amountCents == 50_00)
        #expect(debt.day == lentOn)
    }

    // MARK: Editing a Loan or Debt with payments

    @Test func aLoanWithPaymentsCanStillBeEditedAndWhatIsOutstandingFollows() throws {
        let loan = try lend(100_00)
        let collection = try pay(60_00, on: loan).payment
        #expect(loan.editFlow == .addSheet)

        var editing = TransactionDraft(editing: loan)
        editing.amount = Money(cents: 150_00)
        editing.day = lentOn.adding(days: -2)
        editing.withName = "Pavel"
        editing.note = "Rent help"
        editing.reminderDay = paidOn.adding(days: 30)
        try loan.update(with: editing)

        #expect(loan.amountCents == -150_00)
        #expect(loan.day == lentOn.adding(days: -2))
        #expect(loan.withName == "Pavel")
        #expect(loan.note == "Rent help")
        #expect(loan.reminderDay == paidOn.adding(days: 30))
        #expect(try outstanding(loan) == Money(cents: 90_00))
        #expect(try loan.related(in: context) == [collection])
        #expect(collection.amountCents == 60_00)
        #expect(collection.day == paidOn)
    }

    @Test func aLoanWithPaymentsKeepsItsWalletTypeAndCategory() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        let editing = TransactionDraft(editing: loan)
        #expect(editing.isLockedByPayments)

        var otherWallet = editing
        otherWallet.wallet = savings
        var otherCategory = editing
        otherCategory.category = try context.lockedCategory(.debt)
        var otherType = editing
        otherType.type = .expense
        otherType.category = try store.category("Café")

        #expect(throws: DebtLoanRuleError.lockedByPayments) { try loan.update(with: otherWallet) }
        #expect(throws: DebtLoanRuleError.lockedByPayments) { try loan.update(with: otherCategory) }
        #expect(throws: DebtLoanRuleError.lockedByPayments) { try loan.update(with: otherType) }
        #expect(loan.wallet == checking)
        #expect(loan.category == (try context.lockedCategory(.loan)))
    }

    @Test func aLoansAmountCantDropBelowWhatHasBeenPaid() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)
        var editing = TransactionDraft(editing: loan)

        editing.amount = Money(cents: 59_99)
        #expect(!editing.canSave)
        #expect(throws: DebtLoanRuleError.amountBelowPaid) { try loan.update(with: editing) }
        #expect(loan.amountCents == -100_00)

        editing.amount = Money(cents: 60_00)
        try loan.update(with: editing)
        #expect(try isSettled(loan))
    }

    @Test func aLoanWithoutPaymentsIsEditedFreely() throws {
        let loan = try lend(100_00)

        #expect(!TransactionDraft(editing: loan).isLockedByPayments)
    }

    @Test func aDuplicateOfALoanWithPaymentsStartsUnpaidAndUnlinked() throws {
        let loan = try lend(100_00)
        try pay(60_00, on: loan)
        #expect(loan.canBeDuplicated)

        let copy = try Transaction.create(TransactionDraft(duplicating: loan, on: paidOn), in: context)

        #expect(copy.linkID == nil)
        #expect(try outstanding(copy) == Money(cents: 100_00))
        #expect(try outstanding(loan) == Money(cents: 40_00))
    }

    // MARK: Linking a payment recorded elsewhere

    /// A Debt Collection that came in without a link, as an import brings them.
    private func unlinkedPayment(_ role: LockedRole, _ cents: Int) throws -> Transaction {
        let payment = Transaction(amount: Money(cents: cents), day: paidOn, wallet: checking, category: nil)
        context.insert(payment)
        payment.category = try context.lockedCategory(role)
        payment.isExcludedFromReport = true
        return payment
    }

    @Test func linkingADebtCollectionCountsItAgainstTheLoan() throws {
        let loan = try lend(100_00)
        let collection = try unlinkedPayment(.debtCollection, 100_00)
        #expect(try outstanding(loan) == Money(cents: 100_00))

        try loan.linkPayment(collection)

        #expect(try isSettled(loan))
        #expect(try loan.related(in: context) == [collection])
        #expect(loan.amountCents == -100_00)
    }

    @Test func aPaymentOfTheOtherKindCantBeLinked() throws {
        let loan = try lend(100_00)
        let repayment = try unlinkedPayment(.repayment, -100_00)

        #expect(throws: DebtLoanRuleError.paymentDoesNotMatch) { try loan.linkPayment(repayment) }
        #expect(repayment.linkID == nil)
        #expect(try outstanding(loan) == Money(cents: 100_00))
    }

    // MARK: Debts & Loans

    @Test func debtsAndLoansListsOpenOnesOldestFirstAndSettledOnesNewestFirst() throws {
        let pasha = try lend(100_00, to: "Pasha")
        let anna = try borrow(50_00, from: "Anna")
        anna.day = lentOn.adding(days: -10)
        let ivan = try lend(20_00, to: "Ivan")
        ivan.day = lentOn.adding(days: 1)
        try pay(20_00, on: ivan)
        let olga = try borrow(30_00, from: "Olga")
        try pay(30_00, on: olga)
        try pay(60_00, on: pasha)
        store.spend(4_50, on: try store.category("Café"))

        let list = try DebtsAndLoans(in: context)

        #expect(list.open.map(\.original) == [anna, pasha])
        #expect(list.open.map(\.outstanding) == [Money(cents: 50_00), Money(cents: 40_00)])
        #expect(list.settled.map(\.original) == [ivan, olga])
    }

    @Test func onlyALoanOrDebtTakesPayments() throws {
        let coffee = store.spend(4_50, on: try store.category("Café"))

        #expect(throws: DebtLoanRuleError.notALoanOrDebt) {
            try DebtPaymentDraft(settling: coffee, on: paidOn, in: context)
        }
    }
}
