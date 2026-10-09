import SwiftData
import Testing
@testable import Grosh

@MainActor
struct WalletManagementTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
    }

    @discardableResult
    private func addWallet(_ name: String, startingBalance cents: Int = 0, on day: CalendarDay? = nil) throws -> Wallet {
        try Wallet.create(
            name: name,
            startingBalance: Money(cents: cents),
            on: day ?? today,
            in: context
        )
    }

    @Test func aNewWalletRecordsItsMoneyAsAStartingBalanceTransaction() throws {
        let lastWeek = CalendarDay(year: 2026, month: 10, day: 2)
        let savings = try addWallet("Savings", startingBalance: 1_250_00, on: lastWeek)

        let transactions = savings.transactions ?? []
        #expect(transactions.count == 1)
        let starting = try #require(transactions.first)
        #expect(starting.amount == Money(cents: 1_250_00))
        #expect(starting.day == lastWeek)
        #expect(starting.category?.name == "Starting balance")
        #expect(starting.category?.lockedRole == .startingBalance)
        #expect(starting.isExcludedFromReport)
        #expect(savings.balance(asOf: today) == Money(cents: 1_250_00))
    }

    @Test func aWalletNeedsAName() throws {
        var draft = WalletDraft()
        draft.name = "  "

        #expect(throws: WalletRuleError.missingName) {
            try Wallet.create(draft, startingBalance: Money(cents: 100_00), on: today, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<Wallet>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func editingAWalletSavesItsFieldsAndKeepsItsTransactions() throws {
        let cash = try addWallet("Cash", startingBalance: 40_00)
        var draft = WalletDraft(cash)
        draft.name = " Pocket money "
        draft.symbolName = "banknote.fill"
        draft.color = .orange
        draft.includeInTotal = false

        try cash.update(with: draft)

        #expect(cash.name == "Pocket money")
        #expect(cash.symbolName == "banknote.fill")
        #expect(cash.color == .orange)
        #expect(!cash.includeInTotal)
        #expect(cash.balance(asOf: today) == Money(cents: 40_00))

        draft.name = ""
        #expect(throws: WalletRuleError.missingName) { try cash.update(with: draft) }
        #expect(cash.name == "Pocket money")
    }

    @Test func editingAStartingBalanceKeepsTheSignAsEntered() throws {
        let creditLine = try addWallet("Credit line", startingBalance: -250_00)
        let starting = try #require(creditLine.transactions?.first)
        var edit = StartingBalanceDraft(editing: starting)
        #expect(edit.amount == Money(cents: -250_00))

        edit.amount = Money(cents: -300_00)
        edit.day = CalendarDay(year: 2026, month: 9, day: 1)
        edit.note = " Balance on the September statement "
        try starting.update(with: edit)

        #expect(starting.amount == Money(cents: -300_00))
        #expect(starting.day == CalendarDay(year: 2026, month: 9, day: 1))
        #expect(starting.note == "Balance on the September statement")
        #expect(starting.category?.lockedRole == .startingBalance)
        #expect(starting.isExcludedFromReport)
        #expect(creditLine.balance(asOf: today) == Money(cents: -300_00))

        edit.amount = Money(cents: 1_000_00)
        try starting.update(with: edit)
        #expect(creditLine.balance(asOf: today) == Money(cents: 1_000_00))
    }

    @Test func onlyAStartingBalanceTakesAStartingBalanceEdit() throws {
        let checking = try addWallet("Checking")
        let salary = Transaction(amount: Money(cents: 2_000_00), day: today, wallet: nil, category: nil)
        context.insert(salary)
        salary.wallet = checking
        salary.category = try context.lockedCategory(.otherIncome)
        var edit = StartingBalanceDraft(editing: salary)
        edit.amount = Money(cents: -5_00)

        #expect(throws: TransactionRuleError.notAStartingBalance) { try salary.update(with: edit) }
        #expect(salary.amount == Money(cents: 2_000_00))
    }

    private func unarchivedNames() throws -> [String] {
        try context.fetch(Wallet.unarchived).map(\.name)
    }

    @Test func newWalletsJoinTheEndOfTheList() throws {
        try addWallet("Checking")
        try addWallet("Cash")
        try addWallet("Savings")

        #expect(try unarchivedNames() == ["Checking", "Cash", "Savings"])
    }

    @Test func theOrderSetByDragIsTheOrderEverywhere() throws {
        try addWallet("Checking")
        try addWallet("Cash")
        try addWallet("Savings")

        Wallet.move(try context.fetch(Wallet.unarchived), fromOffsets: [2], toOffset: 0)

        #expect(try unarchivedNames() == ["Savings", "Checking", "Cash"])
        try addWallet("Brokerage")
        #expect(try unarchivedNames() == ["Savings", "Checking", "Cash", "Brokerage"])
    }

    @Test func draggingAWalletDownPlacesItWhereItWasDropped() throws {
        try addWallet("Checking")
        try addWallet("Cash")
        try addWallet("Savings")

        // SwiftUI's onMove reports the drop offset in the list before the move.
        Wallet.move(try context.fetch(Wallet.unarchived), fromOffsets: [0], toOffset: 2)

        #expect(try unarchivedNames() == ["Cash", "Checking", "Savings"])
    }

    @Test func anArchivedWalletLeavesThePickersAndTheTotalButKeepsItsTransactions() throws {
        let checking = try addWallet("Checking", startingBalance: 100_00)
        let oldBank = try addWallet("Old bank", startingBalance: 300_00)

        oldBank.archive()

        #expect(try unarchivedNames() == ["Checking"])
        #expect(Wallet.total(of: try context.fetch(FetchDescriptor<Wallet>()), asOf: today) == Money(cents: 100_00))
        #expect(oldBank.transactions?.count == 1)
        #expect(oldBank.balance(asOf: today) == Money(cents: 300_00))
        #expect(checking.isArchived == false)
    }

    @Test func anUnarchivedWalletReturnsToItsPlaceInTheUsersOrder() throws {
        try addWallet("Checking")
        let oldBank = try addWallet("Old bank", startingBalance: 300_00)
        try addWallet("Cash")
        oldBank.archive()

        oldBank.unarchive()

        #expect(try unarchivedNames() == ["Checking", "Old bank", "Cash"])
        #expect(Wallet.total(of: try context.fetch(Wallet.unarchived), asOf: today) == Money(cents: 300_00))
    }
}
