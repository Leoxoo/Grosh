import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Account → Export CSV, and restoring the export with Import from MoneyLover ("Replace all data"). Every fixture here
/// is made up.
@MainActor
struct GroshCSVExportTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 10)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
    }

    /// A MoneyLover export holding `rows`, each written as MoneyLover does after its header.
    private func moneyLoverExport(_ rows: String...) -> String {
        (["Id,Date,Category,Amount,Currency,Wallet,Note,With,Event,Exclude from report,Members"] + rows)
            .joined(separator: "\r\n") + "\r\n"
    }

    /// A Grosh export holding `rows` after its header.
    private func groshExport(_ rows: String...) -> String {
        ([GroshCSVExport.header.joined(separator: ",")] + rows).map { $0 + "\r\n" }.joined()
    }

    @discardableResult
    private func importing(_ csv: String) throws -> MoneyLoverImportSummary {
        try MoneyLoverImport.replaceAllData(with: MoneyLoverCSV.rows(in: csv), in: context)
    }

    private func exported() throws -> String {
        try GroshCSVExport.csv(in: context)
    }

    private func wallet(_ name: String) throws -> Wallet {
        try #require(try context.fetch(FetchDescriptor<Wallet>()).first { $0.name == name })
    }

    private func cards() throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>(sortBy: [SortDescriptor(\.sortOrder)]))
    }

    // MARK: Export

    @Test func everyTransactionIsListedAsMoneyLoverDoesWithItsCardAndLink() throws {
        try importing(moneyLoverExport(
            "1,10/06/2026,Outgoing transfer,-250,USD,Checking (Navy Federal),To savings,,,✅,",
            "2,10/06/2026,Incoming transfer,250,USD,Savings,To savings,,,✅,",
            "3,10/05/2026,Café,-3.5,USD,Checking (Navy Federal),\"Coffee, large #chase\",Sam,Road trip,,"
        ))

        #expect(try exported() == groshExport(
            "1,10/06/2026,Outgoing transfer,-250.00,USD,Checking (Navy Federal),To savings,,,1,,,1",
            "2,10/06/2026,Incoming transfer,250.00,USD,Savings,To savings,,,1,,,1",
            "3,10/06/2026,Starting balance,0.00,USD,Savings,,,,1,,,",
            "4,10/05/2026,Café,-3.50,USD,Checking (Navy Federal),\"Coffee, large\",Sam,Road trip,,,Chase,",
            "5,10/05/2026,Starting balance,0.00,USD,Checking (Navy Federal),,,,1,,,"
        ))
    }

    @Test func linksAreNumberedInTheOrderTheFileFirstListsThem() throws {
        try importing(moneyLoverExport(
            "1,10/08/2026,Debt Collection,50,USD,Cash,,Sam,,,",
            "2,10/06/2026,Outgoing transfer,-250,USD,Checking,,,,,",
            "3,10/06/2026,Incoming transfer,250,USD,Savings,,,,,",
            "4,10/05/2026,Loan,-50,USD,Cash,,Sam,,,"
        ))

        let links = try MoneyLoverCSV.rows(in: exported()).map(\.link)
        // Debt Collection, the transfer's halves, two Starting balances, the Loan, and Cash's Starting balance.
        #expect(links == ["1", "2", "2", "", "", "1", ""])
    }

    @Test func fieldsHoldingCommasQuotesOrLineBreaksAreQuoted() throws {
        try importing(moneyLoverExport("1,10/05/2026,Café,-3.00,USD,Cash,\"Two \"\"flat\"\" whites,\nto go\",,,,"))

        #expect(try exported().contains(",Cash,\"Two \"\"flat\"\" whites,\nto go\","))
    }

    @Test(arguments: [(-74_91, "-74.91"), (1_000_00, "1000.00"), (-5, "-0.05"), (0, "0.00"), (50, "0.50")])
    func amountsHaveTwoDecimals(cents: Int, text: String) {
        #expect(Money(cents: cents).decimalString == text)
        #expect(Money(decimalString: text) == Money(cents: cents))
    }

    @Test func theFileIsNamedForTheDayItIsExported() {
        #expect(GroshCSVExport.fileName(on: CalendarDay(year: 2026, month: 3, day: 7)) == "Grosh 2026-03-07.csv")
    }

    // MARK: Restore

    @Test func exportImportExportGivesTheSameFile() throws {
        try importing(moneyLoverExport(
            "1,10/12/2026,Rent,-900,USD,Checking (Navy Federal),Next month,,,,",
            "2,10/08/2026,Debt Collection,50,USD,Cash,Paid back,Sam,,✅,",
            "3,10/06/2026,Outgoing transfer,-250,USD,Checking (Navy Federal),To savings,,,✅,",
            "4,10/06/2026,Incoming transfer,250,USD,Savings,To savings,,,✅,",
            "5,10/06/2026,Outgoing transfer,-30,USD,Savings,Sent out,,,✅,",
            "6,10/05/2026,Café,-3.5,USD,Checking (Navy Federal),\"Coffee, \"\"large\"\"\nfor two #chase\",Sam,Trip,,",
            "7,10/05/2026,Loan,-50,USD,Cash,Lunch money,Sam,,✅,",
            "8,10/04/2026,Salary,2000,USD,Checking (Navy Federal),#checking,,,,",
            "9,10/04/2026,Café,-4,USD,Cash,#citi lunch,,,,"
        ))
        let first = try exported()

        try importing(first)

        #expect(try exported() == first)
    }

    @Test func aGroshExportIsRestoredAsItWasExported() throws {
        let export = groshExport(
            "1,10/06/2026,Outgoing transfer,-250.00,USD,Checking,To savings,,,1,,,1",
            "2,10/06/2026,Incoming transfer,250.00,USD,Savings,To savings,,,1,,,1",
            "3,10/06/2026,Starting balance,500.00,USD,Savings,,,,1,,,",
            "4,10/05/2026,Café,-3.50,USD,Checking,\"Coffee, large\",Sam,Road trip,,,Chase,",
            "5,10/05/2026,Café,-2.00,USD,Checking,#chase espresso,,,,,,",
            "6,10/05/2026,Starting balance,1000.00,USD,Checking,,,,1,,,"
        )

        let summary = try importing(export)

        #expect(try exported() == export)
        #expect(summary.wallets.map(\.name) == ["Checking", "Savings"])
        #expect(summary.wallets.map(\.transactionCount) == [3, 1])
        #expect(summary.cardsCreated == 1)
        #expect(summary.unmatchedRows.isEmpty)
    }

    @Test func aWalletsStartingBalanceIsTheFilesOwnRow() throws {
        try importing(groshExport(
            "1,10/05/2026,Café,-3.50,USD,Checking,,,,,,,",
            "2,10/05/2026,Starting balance,1000.00,USD,Checking,Opened,,,1,,,"
        ))

        let checking = try wallet("Checking")
        let starting = (checking.transactions ?? []).filter { $0.category?.lockedRole == .startingBalance }
        #expect(starting.map(\.amountCents) == [1_000_00])
        #expect(starting.map(\.note) == ["Opened"])
        #expect(starting.allSatisfy(\.isExcludedFromReport))
        #expect(checking.balance(asOf: today) == Money(cents: 996_50))
    }

    @Test func aWalletWithoutAStartingBalanceRowGetsAZeroOne() throws {
        try importing(groshExport("1,10/05/2026,Café,-3.50,USD,Cash,,,,,,,"))

        let starting = try (wallet("Cash").transactions ?? []).filter { $0.category?.lockedRole == .startingBalance }
        #expect(starting.map(\.amountCents) == [0])
    }

    @Test func cardsComeFromTheCardColumnAndHashtagsStayInTheNote() throws {
        try importing(groshExport(
            "1,10/05/2026,Café,-3.50,USD,Checking,#citi coffee,,,,,Chase,",
            "2,10/05/2026,Café,-2.00,USD,Checking,#chase espresso,,,,,,",
            "3,10/04/2026,Café,-5.00,USD,Cash,,,,,,Corner Shop Card,"
        ))

        let imported = try context.fetch(FetchDescriptor<Transaction>(sortBy: Transaction.listOrder)).inListOrder()
            .filter { $0.category?.lockedRole != .startingBalance }
        #expect(imported.map(\.note) == ["#citi coffee", "#chase espresso", ""])
        #expect(imported.map { $0.card?.name } == ["Chase", nil, "Corner Shop Card"])

        let cards = try cards()
        #expect(cards.map(\.name) == ["Chase", "Corner Shop Card"])
        #expect(cards.map(\.kind) == [.credit, .credit])
        #expect(cards.map(\.color) == [.purple, .blue])
        #expect(cards.map(\.payingWallet) == [try wallet("Checking"), try wallet("Cash")])
    }

    @Test func rowsSharingALinkAreLinkedWithoutMatchingTheirAmounts() throws {
        try importing(groshExport(
            "1,10/08/2026,Debt Collection,20.00,USD,Cash,,Sam,,,,,1",
            "2,10/06/2026,Outgoing transfer,-250.00,USD,Checking,,,,,,,2",
            "3,10/05/2026,Incoming transfer,240.00,USD,Savings,,,,,,,2",
            "4,10/05/2026,Loan,-50.00,USD,Cash,,Sam,,,,,1",
            "5,10/04/2026,Outgoing transfer,-30.00,USD,Savings,,,,,,,"
        ))

        let imported = try context.fetch(FetchDescriptor<Transaction>(sortBy: Transaction.listOrder)).inListOrder()
            .filter { $0.category?.lockedRole != .startingBalance }
        let links = imported.map(\.linkID)
        #expect(links[0] != nil && links[0] == links[3])
        #expect(links[1] != nil && links[1] == links[2])
        #expect(links[0] != links[1])
        #expect(links[4] == nil)
        #expect(!imported[4].isBalanceAdjustment)
        #expect(imported[4].category?.lockedRole == .outgoingTransfer)
    }
}
