import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Reimbursements: money someone paid back against an Expense, kept as entries on it. The Expense's net is its amount
/// plus its entries, and no transaction is made.
@MainActor
@Suite(.namedInTheLog)
struct ReimbursementTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var today: CalendarDay { store.today }

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A dinner of $60 on the 3rd, the Expense most tests pay back.
    private func dinner() throws -> Transaction {
        try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
    }

    @discardableResult
    private func payBack(
        _ cents: Int, on paidOn: CalendarDay? = nil, note: String = "", to expense: Transaction
    ) throws -> Reimbursement {
        try Reimbursement.add(
            ReimbursementDraft(amount: Money(cents: cents), day: paidOn ?? today, note: note), to: expense, in: context
        )
    }

    private func storedTransactionCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Transaction>())
    }

    // MARK: The net

    @Test func anExpenseWithoutReimbursementsNetsItsOwnAmount() throws {
        let dinner = try dinner()

        #expect(dinner.reimbursedCents == 0)
        #expect(dinner.netCents == -60_00)
        #expect(dinner.net == Money(cents: -60_00))
        #expect(dinner.amount == Money(cents: -60_00))
    }

    @Test func aPartialReimbursementLeavesTheRestOfTheExpense() throws {
        let dinner = try dinner()

        try payBack(20_00, to: dinner)

        #expect(dinner.netCents == -40_00)
        #expect(dinner.net == Money(cents: -40_00))
        #expect(dinner.amountCents == -60_00)
    }

    @Test func anExactReimbursementNetsToZero() throws {
        let dinner = try dinner()

        try payBack(60_00, to: dinner)

        #expect(dinner.netCents == 0)
    }

    @Test func anOverReimbursementNetsAboveZero() throws {
        let dinner = try dinner()

        try payBack(100_00, to: dinner)

        #expect(dinner.netCents == 40_00)
    }

    @Test func anExpenseCanHaveAnyNumberOfReimbursements() throws {
        let dinner = try dinner()

        try payBack(20_00, on: day(2026, 10, 5), to: dinner)
        try payBack(15_00, on: day(2026, 10, 4), note: "Sam's share", to: dinner)
        try payBack(5_00, on: day(2026, 10, 9), to: dinner)

        #expect(dinner.reimbursedCents == 40_00)
        #expect(dinner.netCents == -20_00)
        #expect(dinner.orderedReimbursements.map(\.amountCents) == [15_00, 20_00, 5_00])
        #expect(dinner.orderedReimbursements.map(\.note) == ["Sam's share", "", ""])
    }

    @Test func aReimbursementIsAnEntryOnTheExpenseNotATransaction() throws {
        let dinner = try dinner()

        let entry = try payBack(20_00, on: day(2026, 10, 5), note: "  Sam  ", to: dinner)

        #expect(try storedTransactionCount() == 1)
        #expect(entry.expense === dinner)
        #expect(entry.amount == Money(cents: 20_00))
        #expect(entry.day == day(2026, 10, 5))
        #expect(entry.note == "Sam")
    }

    @Test func theNetLandsInTheExpensesOwnWalletOnItsOwnDay() throws {
        let dinner = try dinner()

        try payBack(20_00, on: day(2026, 10, 8), to: dinner)

        // The Expense's day, 10/3, already holds the net, whatever day the money was paid back on.
        #expect(store.checking.balance(asOf: day(2026, 10, 3)) == Money(cents: -40_00))
        #expect(store.checking.balance(asOf: day(2026, 10, 2)) == Money(cents: 0))
    }

    // MARK: Editing and deleting an entry

    @Test func editingAnEntryChangesTheNet() throws {
        let dinner = try dinner()
        let entry = try payBack(20_00, to: dinner)

        var draft = ReimbursementDraft(editing: entry)
        draft.amount = Money(cents: 35_00)
        draft.day = day(2026, 10, 6)
        draft.note = "Both shares"
        try entry.update(with: draft)

        #expect(entry.amountCents == 35_00)
        #expect(entry.day == day(2026, 10, 6))
        #expect(entry.note == "Both shares")
        #expect(dinner.netCents == -25_00)
        #expect(dinner.reimbursements?.count == 1)
    }

    @Test func aDraftStartsFromTheEntryItEdits() throws {
        let entry = try payBack(20_00, on: day(2026, 10, 6), note: "Sam", to: try dinner())

        let draft = ReimbursementDraft(editing: entry)

        #expect(draft.amount == Money(cents: 20_00))
        #expect(draft.day == day(2026, 10, 6))
        #expect(draft.note == "Sam")
    }

    @Test func anEditThatBreaksTheRulesChangesNothing() throws {
        let dinner = try dinner()
        let entry = try payBack(20_00, to: dinner)

        var draft = ReimbursementDraft(editing: entry)
        draft.amount = Money(cents: 0)
        draft.note = "ignored"

        #expect(throws: ReimbursementRuleError.missingAmount) { try entry.update(with: draft) }
        #expect(entry.amountCents == 20_00)
        #expect(entry.note == "")
        #expect(dinner.netCents == -40_00)
    }

    @Test func deletingAnEntryBringsTheNetBackUp() throws {
        let dinner = try dinner()
        let first = try payBack(20_00, to: dinner)
        let second = try payBack(10_00, to: dinner)

        try first.delete()

        #expect(dinner.orderedReimbursements == [second])
        #expect(dinner.netCents == -50_00)
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 1)

        try second.delete()

        #expect(dinner.reimbursedCents == 0)
        #expect(dinner.netCents == -60_00)
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 0)
        #expect(try storedTransactionCount() == 1)
    }

    // MARK: Which transactions

    @Test func anAmountPaidBackMustBeAboveZero() throws {
        let dinner = try dinner()

        #expect(throws: ReimbursementRuleError.missingAmount) { try payBack(0, to: dinner) }
        #expect(throws: ReimbursementRuleError.missingAmount) { try payBack(-5_00, to: dinner) }
        #expect(dinner.reimbursements?.isEmpty == true)
    }

    @Test func onlyAnExpenseCanBePaidBack() throws {
        let salary = try store.record(1_500_00, "Salary", .income, on: day(2026, 10, 5))
        let loan = try store.lendOrBorrow(.loan, 250_00, on: day(2026, 9, 20))
        let refund = try store.record(30_00, "Clothing", on: day(2026, 10, 6))
        var transfer = TransferDraft(day: day(2026, 10, 4))
        transfer.from = store.checking
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        transfer.to = savings
        transfer.amount = Money(cents: 100_00)
        let made = try Transfer.create(transfer, in: context)

        for notAnExpense in [salary, loan, refund, made.outgoing, made.incoming] {
            #expect(!notAnExpense.canBeReimbursed)
            #expect(throws: ReimbursementRuleError.notAnExpense) { try payBack(10_00, to: notAnExpense) }
        }
        #expect(try dinner().canBeReimbursed)
        #expect(try context.fetchCount(FetchDescriptor<Reimbursement>()) == 0)
    }
}
