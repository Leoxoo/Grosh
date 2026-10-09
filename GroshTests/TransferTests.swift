import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Transfers between wallets (ADR-0002): two linked transactions, an Outgoing transfer in the source wallet and an
/// Incoming transfer in the destination.
@MainActor
struct TransferTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)
    private let checking: Wallet
    private let savings: Wallet

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
        checking = try Wallet.create(
            name: "Checking", startingBalance: Money(cents: 1_000_00), on: today, in: container.mainContext
        )
        savings = try Wallet.create(
            name: "Savings", startingBalance: Money(cents: 0), on: today, in: container.mainContext
        )
    }

    /// A transfer of `cents` from Checking to Savings, dated today.
    private func draft(_ cents: Int, note: String = "") -> TransferDraft {
        var draft = TransferDraft(day: today)
        draft.from = checking
        draft.to = savings
        draft.amount = Money(cents: cents)
        draft.note = note
        return draft
    }

    // MARK: Making a transfer

    @Test func aTransferMovesTheAmountFromOneWalletToTheOther() throws {
        try Transfer.create(draft(250_00), in: context)

        #expect(checking.balance(asOf: today) == Money(cents: 750_00))
        #expect(savings.balance(asOf: today) == Money(cents: 250_00))
    }

    @Test func aNewTransferStartsTodayFromTheLastUsedWalletToTheFirstOtherOne() throws {
        var spent = TransactionDraft(type: .income, day: today)
        spent.wallet = savings
        spent.amount = Money(cents: 20_00)
        spent.category = try context.lockedCategory(.otherIncome)
        try Transaction.create(spent, in: context)

        let suggested = TransactionDefaults.suggestTransfer(on: today, in: context)

        #expect(suggested.from == savings)
        #expect(suggested.to == checking)
        #expect(suggested.day == today)
    }

    @Test func aTransferStartedWhileViewingAWalletStartsFromThatWallet() throws {
        let cash = try Wallet.create(name: "Cash", startingBalance: Money(cents: 0), on: today, in: context)

        let suggested = TransactionDefaults.suggestTransfer(on: today, viewing: cash, in: context)

        #expect(suggested.from == cash)
        #expect(suggested.to == checking)
    }

    @Test func bothHalvesCarryTheDateAndNoteEntered() throws {
        var entered = draft(250_00, note: "  Rainy day fund\n")
        entered.day = CalendarDay(year: 2026, month: 10, day: 3)

        let transfer = try Transfer.create(entered, in: context)

        for half in [transfer.outgoing, transfer.incoming] {
            #expect(half.day == CalendarDay(year: 2026, month: 10, day: 3))
            #expect(half.note == "Rainy day fund")
        }
    }

    @Test func eachHalfListsTheOtherAsItsRelatedTransaction() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        try Transfer.create(draft(10_00), in: context)

        #expect(try transfer.outgoing.related(in: context) == [transfer.incoming])
        #expect(try transfer.incoming.related(in: context) == [transfer.outgoing])
    }

    // MARK: Required fields

    @Test func aDraftWithTwoWalletsAndAnAmountCanBeSaved() {
        #expect(draft(250_00).canSave)
    }

    @Test func aTransferIsRefusedWithoutTheWalletTheMoneyLeaves() throws {
        var entered = draft(250_00)
        entered.from = nil

        try expectRefused(entered, because: .missingSourceWallet)
    }

    @Test func aTransferIsRefusedWithoutTheWalletTheMoneyGoesTo() throws {
        var entered = draft(250_00)
        entered.to = nil

        try expectRefused(entered, because: .missingDestinationWallet)
    }

    @Test func aTransferIsRefusedFromAWalletToItself() throws {
        var entered = draft(250_00)
        entered.to = checking

        try expectRefused(entered, because: .sameWallet)
    }

    @Test func aTransferIsRefusedWithoutAnAmount() throws {
        try expectRefused(draft(0), because: .missingAmount)
    }

    /// Saving `draft` throws `error`, Save stays disabled, and no transaction is recorded.
    private func expectRefused(_ draft: TransferDraft, because error: TransferRuleError) throws {
        let before = try context.fetchCount(FetchDescriptor<Transaction>())

        #expect(!draft.canSave)
        #expect(throws: error) { try Transfer.create(draft, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == before)
    }

    // MARK: Editing a half

    @Test func eachHalfIsEditedAsATransferHalfAndNeverDuplicated() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)

        for half in [transfer.outgoing, transfer.incoming] {
            #expect(half.editFlow == .transferHalf)
            #expect(!half.canBeDuplicated)
        }
    }

    @Test func changingTheAmountAsksWhetherToUpdateBothHalves() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var edited = TransferHalfDraft(editing: transfer.outgoing)
        edited.amount = Money(cents: 255_00)

        #expect(try transfer.outgoing.updateScopes(for: edited, in: context) == [.bothHalves, .onlyThisOne])
    }

    @Test func changingTheDateAsksWhetherToUpdateBothHalves() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var edited = TransferHalfDraft(editing: transfer.incoming)
        edited.day = CalendarDay(year: 2026, month: 10, day: 8)

        #expect(try transfer.incoming.updateScopes(for: edited, in: context) == [.bothHalves, .onlyThisOne])
    }

    @Test func changingOnlyTheNoteChangesThisHalfWithoutAsking() throws {
        let transfer = try Transfer.create(draft(250_00, note: "Rainy day fund"), in: context)
        var edited = TransferHalfDraft(editing: transfer.incoming)
        edited.note = "Emergency fund"

        #expect(try transfer.incoming.updateScopes(for: edited, in: context) == [.onlyThisOne])
        try transfer.incoming.update(with: edited, .onlyThisOne, in: context)
        #expect(transfer.incoming.note == "Emergency fund")
        #expect(transfer.outgoing.note == "Rainy day fund")
    }

    @Test func aHalfWhoseOtherHalfWasDeletedIsChangedWithoutAsking() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        try transfer.incoming.delete(.onlyThisOne, in: context)
        var edited = TransferHalfDraft(editing: transfer.outgoing)
        edited.amount = Money(cents: 255_00)

        #expect(transfer.outgoing.editFlow == .transferHalf)
        #expect(try transfer.outgoing.updateScopes(for: edited, in: context) == [.onlyThisOne])
    }

    @Test func changingOnlyThisOneLeavesTheHalvesDifferentLikeAFee() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var edited = TransferHalfDraft(editing: transfer.outgoing)
        edited.amount = Money(cents: 255_00)

        try transfer.outgoing.update(with: edited, .onlyThisOne, in: context)

        #expect(checking.balance(asOf: today) == Money(cents: 745_00))
        #expect(savings.balance(asOf: today) == Money(cents: 250_00))
        #expect(Wallet.total(of: [checking, savings], asOf: today) == Money(cents: 995_00))
    }

    @Test func updatingBothGivesTheOtherHalfTheNewAmount() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var edited = TransferHalfDraft(editing: transfer.incoming)
        edited.amount = Money(cents: 300_00)

        try transfer.incoming.update(with: edited, .bothHalves, in: context)

        #expect(checking.balance(asOf: today) == Money(cents: 700_00))
        #expect(savings.balance(asOf: today) == Money(cents: 300_00))
    }

    @Test func updatingBothMovesTheOtherHalfToTheNewDateAndKeepsAFeeTakenBefore() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var fee = TransferHalfDraft(editing: transfer.outgoing)
        fee.amount = Money(cents: 255_00)
        try transfer.outgoing.update(with: fee, .onlyThisOne, in: context)
        var moved = TransferHalfDraft(editing: transfer.outgoing)
        moved.day = CalendarDay(year: 2026, month: 10, day: 2)

        try transfer.outgoing.update(with: moved, .bothHalves, in: context)

        #expect(transfer.incoming.day == CalendarDay(year: 2026, month: 10, day: 2))
        #expect(transfer.incoming.amount == Money(cents: 250_00))
        #expect(transfer.outgoing.amount == Money(cents: -255_00))
    }

    @Test func anEditWithoutAnAmountIsRefusedAndChangesNeitherHalf() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        var edited = TransferHalfDraft(editing: transfer.outgoing)
        edited.amount = Money(cents: 0)

        #expect(!edited.canSave)
        #expect(throws: TransferRuleError.missingAmount) {
            try transfer.outgoing.update(with: edited, .bothHalves, in: context)
        }
        #expect(transfer.outgoing.amount == Money(cents: -250_00))
        #expect(transfer.incoming.amount == Money(cents: 250_00))
    }

    @Test func onlyATransferHalfTakesATransferHalfEdit() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)
        let startingBalance = try #require(savings.transactions?.first { !$0.category!.isTransferHalf })

        #expect(throws: TransferRuleError.notATransferHalf) {
            try startingBalance.update(with: TransferHalfDraft(editing: transfer.incoming), .onlyThisOne, in: context)
        }
        #expect(startingBalance.amount == Money(cents: 0))
    }

    // MARK: Deleting a half

    @Test func deletingAHalfAsksWhetherToDeleteBoth() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)

        #expect(try transfer.incoming.deleteScopes(in: context) == [.withRelated, .onlyThisOne])
        #expect(TransactionDeleteScope.withRelated.buttonTitle(relatedCount: 1) == "Delete Both")
    }

    @Test func deletingBothHalvesUndoesTheTransfer() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)

        try transfer.outgoing.delete(.withRelated, in: context)

        #expect(checking.balance(asOf: today) == Money(cents: 1_000_00))
        #expect(savings.balance(asOf: today) == Money(cents: 0))
    }

    @Test func deletingOnlyThisOneKeepsTheOtherHalf() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)

        try transfer.outgoing.delete(.onlyThisOne, in: context)

        #expect(checking.balance(asOf: today) == Money(cents: 1_000_00))
        #expect(savings.balance(asOf: today) == Money(cents: 250_00))
        #expect(try transfer.incoming.related(in: context).isEmpty)
    }

    // MARK: Income, spending and the Total

    @Test func aTransferLeavesTheTotalUnchanged() throws {
        try Transfer.create(draft(250_00), in: context)

        #expect(Wallet.total(of: [checking, savings], asOf: today) == Money(cents: 1_000_00))
    }

    @Test func neitherHalfOfATransferCountsAsIncomeOrSpending() throws {
        let transfer = try Transfer.create(draft(250_00), in: context)

        #expect(!transfer.outgoing.countsInReport)
        #expect(!transfer.incoming.countsInReport)
    }

    @Test func anOrdinaryTransactionCountsAsIncomeOrSpendingUnlessExcludedFromReport() throws {
        var coffee = TransactionDraft(type: .expense, day: today)
        coffee.wallet = checking
        coffee.amount = Money(cents: 4_50)
        coffee.category = try #require(try context.fetch(FetchDescriptor<Grosh.Category>()).first { $0.name == "Café" })
        let counted = try Transaction.create(coffee, in: context)
        coffee.isExcludedFromReport = true
        let excluded = try Transaction.create(coffee, in: context)

        #expect(counted.countsInReport)
        #expect(!excluded.countsInReport)
    }
}
