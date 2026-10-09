import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Saving what the Add Transaction sheet holds: signs, required fields and the Card rule.
@MainActor
struct AddTransactionTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(name: "Checking", startingBalance: Money(cents: 0), on: today, in: container.mainContext)
    }

    private func category(_ name: String, _ type: CategoryType = .expense) throws -> Grosh.Category {
        try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == name && $0.type == type })
    }

    /// A draft of `type` in Checking for `cents`, filed under `categoryName`.
    private func draft(_ type: CategoryType, _ cents: Int, _ categoryName: String) throws -> TransactionDraft {
        var draft = TransactionDraft(type: type, day: today)
        draft.wallet = checking
        draft.amount = Money(cents: cents)
        draft.category = try category(categoryName, type)
        return draft
    }

    @Test func savingAnExpenseTakesTheAmountOutOfTheWallet() throws {
        try Transaction.create(try draft(.expense, 1276, "Café"), in: context)

        #expect(checking.balance(asOf: today) == Money(cents: -1276))
    }

    @Test(arguments: [
        (CategoryType.income, "Salary", 1276),
        (.debtLoan, "Loan", -1276),
        (.debtLoan, "Debt", 1276),
    ])
    func theCategorySetsTheSign(type: CategoryType, categoryName: String, expectedCents: Int) throws {
        try Transaction.create(try draft(type, 1276, categoryName), in: context)

        #expect(checking.balance(asOf: today) == Money(cents: expectedCents))
    }

    @Test func theTransactionKeepsWhatWasEntered() throws {
        var entered = try draft(.expense, 1276, "Café")
        entered.note = "Latte #treat"
        entered.withName = "Anna"
        entered.day = CalendarDay(year: 2026, month: 10, day: 7)
        entered.isExcludedFromReport = true

        let transaction = try Transaction.create(entered, in: context)

        #expect(transaction.wallet == checking)
        #expect(transaction.category == (try category("Café")))
        #expect(transaction.note == "Latte #treat")
        #expect(transaction.withName == "Anna")
        #expect(transaction.day == CalendarDay(year: 2026, month: 10, day: 7))
        #expect(transaction.isExcludedFromReport)
    }

    @Test func theNoteAndWithAreSavedWithoutSurroundingSpaces() throws {
        var entered = try draft(.expense, 1276, "Café")
        entered.note = "  Latte\n"
        entered.withName = " Anna "

        let transaction = try Transaction.create(entered, in: context)

        #expect(transaction.note == "Latte")
        #expect(transaction.withName == "Anna")
    }

    // MARK: Required fields

    @Test func aDraftWithWalletAmountAndCategoryCanBeSaved() throws {
        #expect(try draft(.expense, 1276, "Café").canSave)
    }

    @Test func savingIsRefusedWithoutAWallet() throws {
        var entered = try draft(.expense, 1276, "Café")
        entered.wallet = nil

        #expect(!entered.canSave)
        #expect(throws: TransactionRuleError.missingWallet) { try Transaction.create(entered, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1) // just the Starting balance
    }

    @Test(arguments: [0, -500])
    func savingIsRefusedWithoutAnAmountAboveZero(cents: Int) throws {
        let entered = try draft(.expense, cents, "Café")

        #expect(!entered.canSave)
        #expect(throws: TransactionRuleError.missingAmount) { try Transaction.create(entered, in: context) }
    }

    @Test func savingIsRefusedWithoutACategory() throws {
        var entered = try draft(.expense, 1276, "Café")
        entered.category = nil

        #expect(!entered.canSave)
        #expect(throws: TransactionRuleError.missingCategory) { try Transaction.create(entered, in: context) }
    }

    // MARK: Card rule

    @discardableResult
    private func addCard(_ name: String, paidFrom wallet: Wallet) throws -> Card {
        try Card.create(CardDetails(name: name, kind: .credit, payingWallet: wallet), in: context)
    }

    @Test func anExpenseNeedsACardWhenItsWalletHasOne() throws {
        let appleCard = try addCard("Apple Card", paidFrom: checking)
        var entered = try draft(.expense, 1276, "Café")

        #expect(entered.requiresCard)
        #expect(!entered.canSave)
        #expect(throws: TransactionRuleError.missingCard) { try Transaction.create(entered, in: context) }

        entered.card = appleCard
        let transaction = try Transaction.create(entered, in: context)
        #expect(transaction.card == appleCard)
    }

    @Test func anExpenseNeedsNoCardWhenItsWalletHasNone() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        try addCard("Apple Card", paidFrom: savings)

        let entered = try draft(.expense, 1276, "Café")

        #expect(!entered.requiresCard)
        #expect(entered.canSave)
    }

    @Test func anArchivedCardDoesNotMakeTheCardRequired() throws {
        try addCard("Old Card", paidFrom: checking).archive()

        #expect(try draft(.expense, 1276, "Café").canSave)
    }

    @Test(arguments: [(CategoryType.income, "Salary"), (.debtLoan, "Loan"), (.debtLoan, "Debt")])
    func theCardIsOptionalOnIncomeAndDebtLoan(type: CategoryType, categoryName: String) throws {
        try addCard("Apple Card", paidFrom: checking)

        let entered = try draft(type, 1276, categoryName)

        #expect(!entered.requiresCard)
        #expect(entered.canSave)
    }

    @Test func changingTheWalletClearsTheCard() throws {
        let savings = try Wallet.create(name: "Savings", startingBalance: Money(cents: 0), on: today, in: context)
        var entered = try draft(.expense, 1276, "Café")
        entered.card = try addCard("Apple Card", paidFrom: checking)

        entered.wallet = savings

        #expect(entered.card == nil)
    }

    // MARK: Switching type

    @Test func switchingTypeClearsTheCategory() throws {
        var entered = try draft(.expense, 1276, "Café")

        entered.type = .income

        #expect(entered.category == nil)
    }

    @Test func switchingToDebtLoanExcludesFromReportAndSwitchingBackIncludes() throws {
        var entered = try draft(.expense, 1276, "Café")

        entered.type = .debtLoan
        #expect(entered.isExcludedFromReport)

        entered.type = .income
        #expect(!entered.isExcludedFromReport)
    }

    // MARK: Duplicate and Edit

    /// A Loan of 100.00 to Pasha on 05/27/2026, kept in the report, with a note and a Card.
    private func pashaLoan() throws -> Transaction {
        var entered = try draft(.debtLoan, 10_000, "Loan")
        entered.day = CalendarDay(year: 2026, month: 5, day: 27)
        entered.withName = "Pasha"
        entered.note = "Rent help"
        entered.isExcludedFromReport = false
        entered.card = try addCard("Navy Federal Debit", paidFrom: checking)
        return try Transaction.create(entered, in: context)
    }

    @Test func duplicatingCopiesEverythingButTheDateWhichIsToday() throws {
        let original = try pashaLoan()

        let duplicate = TransactionDraft(duplicating: original, on: today)

        #expect(duplicate.type == .debtLoan)
        #expect(duplicate.wallet == checking)
        #expect(duplicate.amount == Money(cents: 10_000))
        #expect(duplicate.category == (try category("Loan", .debtLoan)))
        #expect(duplicate.card == original.card)
        #expect(duplicate.note == "Rent help")
        #expect(duplicate.withName == "Pasha")
        #expect(!duplicate.isExcludedFromReport)
        #expect(duplicate.day == today)
    }

    @Test func savingADuplicateAddsANewTransactionAndLeavesTheOriginal() throws {
        let original = try pashaLoan()

        let copy = try Transaction.create(TransactionDraft(duplicating: original, on: today), in: context)

        #expect(copy != original)
        #expect(copy.amountCents == -10_000)
        #expect(original.day == CalendarDay(year: 2026, month: 5, day: 27))
        #expect(checking.balance(asOf: today) == Money(cents: -20_000))
    }

    @Test func editingStartsFromTheTransactionAsItIs() throws {
        let original = try pashaLoan()

        let editing = TransactionDraft(editing: original)

        #expect(editing.day == CalendarDay(year: 2026, month: 5, day: 27))
        #expect(editing.amount == Money(cents: 10_000))
        #expect(editing.withName == "Pasha")
    }

    @Test func savingAnEditChangesTheTransactionButKeepsItsPlaceWithinTheDay() throws {
        let original = try pashaLoan()
        let enteredAt = original.createdAt
        var editing = TransactionDraft(editing: original)
        editing.amount = Money(cents: 12_000)
        editing.type = .debtLoan
        editing.category = try category("Debt", .debtLoan)
        editing.note = "Borrowed instead"

        try original.update(with: editing)

        #expect(original.amountCents == 12_000)
        #expect(original.category == (try category("Debt", .debtLoan)))
        #expect(original.note == "Borrowed instead")
        #expect(original.createdAt == enteredAt)
    }

    @Test func anEditThatBreaksARuleChangesNothing() throws {
        let original = try pashaLoan()
        var editing = TransactionDraft(editing: original)
        editing.amount = Money(cents: 0)

        #expect(throws: TransactionRuleError.missingAmount) { try original.update(with: editing) }
        #expect(original.amountCents == -10_000)
    }
}
