import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Every change to what a wallet's balance counts of a transaction (its wallet, day, amount, Reimbursed total and
/// Recently Deleted mark) marks the wallet-months it touches as dirty, so their saved totals are counted again
/// (ADR-0013).
///
/// The suite's store counts nothing in its saves, so the marks a change makes stay in it to be read; ``settle()`` counts
/// them as the app's saves do.
@MainActor
@Suite(.namedInTheLog)
struct DirtyWalletMonthTests {
    private let store: TestStore
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }

    init() throws {
        store = try TestStore(countingEachSave: false)
    }

    /// The wallet-months marked dirty since the last ``settle()``, as "<wallet> <yyyy>-<mm>".
    private func dirty() throws -> Set<String> {
        Set(try marks().map { mark in
            String(format: "%@ %04d-%02d", mark.wallet?.name ?? "-", mark.month.year, mark.month.month)
        })
    }

    private func marks() throws -> [DirtyWalletMonth] {
        try context.fetch(FetchDescriptor<DirtyWalletMonth>())
    }

    /// Saves, then counts the months marked so far and clears their marks, so a test sees only what its own change
    /// marks.
    private func settle() throws {
        try context.save()
        try WalletMonthTotals.countDirtyMonths(in: context)
    }

    private func draft(_ cents: Int, on day: CalendarDay, in wallet: Wallet? = nil) throws -> TransactionDraft {
        var draft = TransactionDraft(type: .expense, day: day)
        draft.wallet = wallet ?? checking
        draft.entry = AmountEntry(cents: cents)
        draft.category = try store.category("Restaurants")
        return draft
    }

    @Test func recordingATransactionMarksItsWalletMonth() throws {
        try settle()

        try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)

        #expect(try dirty() == ["Checking 2026-10"])
    }

    // MARK: Editing

    @Test func editingTheAmountMarksItsMonth() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        var edit = TransactionDraft(editing: dinner)
        edit.entry = AmountEntry(cents: 45_00)
        try dinner.update(with: edit)

        #expect(try dirty() == ["Checking 2026-10"])
    }

    @Test func movingTheDateToAnotherMonthMarksBothMonths() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 3, 14)), in: context)
        try settle()

        var edit = TransactionDraft(editing: dinner)
        edit.day = day(2026, 5, 2)
        try dinner.update(with: edit)

        #expect(try dirty() == ["Checking 2026-03", "Checking 2026-05"])
    }

    @Test func movingToAnotherWalletMarksBothWallets() throws {
        let savings = context.addWallet("Savings")
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        var edit = TransactionDraft(editing: dinner)
        edit.wallet = savings
        try dinner.update(with: edit)

        #expect(try dirty() == ["Checking 2026-10", "Savings 2026-10"])
    }

    @Test func editingWhatNoBalanceCountsMarksNothing() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        var edit = TransactionDraft(editing: dinner)
        edit.note = "Birthday dinner"
        try dinner.update(with: edit)

        #expect(try dirty().isEmpty)
    }

    @Test func changingAMonthTwiceBeforeSavingMarksItOnce() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        let lunch = try Transaction.create(draft(12_00, on: day(2026, 10, 6)), in: context)
        try settle()

        dinner.changeCounted { $0.amountCents = -31_00 }
        lunch.changeCounted { $0.amountCents = -13_00 }
        try context.save()

        #expect(try marks().count == 1)
        #expect(try dirty() == ["Checking 2026-10"])
    }

    @Test func editingAStartingBalanceMarksTheMonthsItLeftAndMovedTo() throws {
        let savings = try Wallet.create(
            name: "Savings", startingBalance: Money(cents: 100_00), on: day(2026, 10, 1), in: context
        )
        let starting = try #require(savings.transactions?.first)
        try settle()

        var edit = StartingBalanceDraft(editing: starting)
        edit.day = day(2026, 9, 1)
        try starting.update(with: edit)

        #expect(try dirty() == ["Savings 2026-09", "Savings 2026-10"])
    }

    @Test func editingBothHalvesOfATransferMarksBothWallets() throws {
        let savings = context.addWallet("Savings")
        var transfer = TransferDraft(day: day(2026, 10, 5))
        transfer.from = checking
        transfer.to = savings
        transfer.entry = AmountEntry(cents: 250_00)
        let made = try Transfer.create(transfer, in: context)
        try settle()

        var edit = TransferHalfDraft(editing: made.outgoing)
        edit.day = day(2026, 11, 1)
        try made.outgoing.update(with: edit, scope: .bothHalves)

        #expect(try dirty() == ["Checking 2026-10", "Checking 2026-11", "Savings 2026-10", "Savings 2026-11"])
    }

    // MARK: Splits and Reimbursements

    @Test func aPartSplitOffOnAnotherDayMarksItsMonth() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        var split = SplitDraft(splitting: dinner)
        var part = split.newPart()
        part.entry = AmountEntry(cents: 10_00)
        part.day = day(2026, 9, 28)
        split.addPart(part)
        try dinner.split(split)

        #expect(try dirty() == ["Checking 2026-09", "Checking 2026-10"])
    }

    @Test func undoingASplitMarksTheMonthsOfItsParts() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        var split = SplitDraft(splitting: dinner)
        var part = split.newPart()
        part.entry = AmountEntry(cents: 10_00)
        part.day = day(2026, 9, 28)
        split.addPart(part)
        try dinner.split(split)
        try settle()

        try dinner.undoSplit()

        #expect(try dirty() == ["Checking 2026-09", "Checking 2026-10"])
    }

    @Test func aReimbursementMarksTheMonthOfItsExpense() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        try context.payBack(10_00, on: day(2026, 11, 2), to: dinner)

        #expect(try dirty() == ["Checking 2026-10"])
    }

    // MARK: Recently Deleted

    @Test func deletingAndRestoringATransactionMarksItsMonth() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try settle()

        try dinner.delete(.onlySelected)
        #expect(try dirty() == ["Checking 2026-10"])

        try settle()
        try dinner.restore()
        #expect(try dirty() == ["Checking 2026-10"])
    }

    @Test func deletingAndRestoringAWalletMarksEveryMonthItHeld() throws {
        try Transaction.create(draft(30_00, on: day(2026, 9, 5)), in: context)
        try Transaction.create(draft(12_00, on: day(2026, 10, 5)), in: context)
        try settle()

        try checking.delete(today: TestStore.today)
        #expect(try dirty() == ["Checking 2026-09", "Checking 2026-10"])

        try settle()
        try checking.restore(today: TestStore.today)
        #expect(try dirty() == ["Checking 2026-09", "Checking 2026-10"])
    }

    @Test func removingATransactionForGoodMarksNothing() throws {
        let dinner = try Transaction.create(draft(30_00, on: day(2026, 10, 5)), in: context)
        try dinner.delete(.onlySelected)
        try settle()

        try RecentlyDeleted.empty(in: context)

        #expect(try dirty().isEmpty)
    }
}
