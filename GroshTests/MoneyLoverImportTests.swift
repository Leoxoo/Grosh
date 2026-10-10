import Foundation
import SwiftData
import Testing
@testable import Grosh

/// Import from MoneyLover ("Replace all data"): a MoneyLover CSV export replaces every wallet, Card and transaction,
/// keeping the categories. Every fixture here is made up.
@MainActor
struct MoneyLoverImportTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let today = CalendarDay(year: 2026, month: 10, day: 10)

    init() throws {
        container = try GroshStore.makeContainer(inMemory: true)
        try CategorySeeder.seedIfNeeded(in: container.mainContext)
    }

    /// A MoneyLover export holding `rows`, each written as MoneyLover does after its header.
    private func export(_ rows: String...) -> String {
        (["Id,Date,Category,Amount,Currency,Wallet,Note,With,Event,Exclude from report,Members"] + rows)
            .joined(separator: "\r\n") + "\r\n"
    }

    @discardableResult
    private func importing(_ csv: String) throws -> MoneyLoverImportSummary {
        try MoneyLoverImport.replaceAllData(with: csv, in: context)
    }

    private func wallet(_ name: String) throws -> Wallet {
        try #require(try context.fetch(FetchDescriptor<Wallet>()).first { $0.name == name })
    }

    /// The wallet's imported transactions, leaving out its Starting balance, in list order.
    private func rows(in name: String) throws -> [Transaction] {
        try (wallet(name).transactions ?? []).filter { $0.category?.lockedRole != .startingBalance }.inListOrder()
    }

    // MARK: Rows

    @Test func eachRowBecomesATransactionInTheWalletItNames() throws {
        try importing(export("1,10/05/2026,Café,-10.91,USD,Checking,Coffee,,,,"))

        let coffee = try #require(try rows(in: "Checking").first)
        #expect(coffee.amountCents == -10_91)
        #expect(coffee.day == CalendarDay(year: 2026, month: 10, day: 5))
        #expect(coffee.category?.name == "Café")
        #expect(coffee.note == "Coffee")
        #expect(try wallet("Checking").balance(asOf: today) == Money(cents: -10_91))
    }

    // MARK: Replacing all data

    /// Data the user had before importing: a wallet with a Card, an expense paid with it, and a category of their own.
    private func addExistingData() throws {
        let old = try Wallet.create(name: "Old wallet", startingBalance: Money(cents: 5_00), on: today, in: context)
        let card = try Card.create(CardDraft(name: "Old card", kind: .debit, payingWallet: old), in: context)
        try CategoryCatalog(context: context).add(CategoryDraft(name: "Hobbies", type: .expense))
        let spent = Transaction(
            amount: Money(cents: -2_00), day: today, wallet: old, category: try context.otherCategory(.expense)
        )
        spent.card = card
        context.insert(spent)
        try context.save()
    }

    @Test func importingReplacesEveryWalletCardAndTransactionButKeepsTheCategories() throws {
        try addExistingData()
        let categoriesBefore = try context.fetchCount(FetchDescriptor<Grosh.Category>())

        try importing(export("1,10/05/2026,Café,-10.91,USD,Checking,Coffee,,,,"))

        #expect(try context.fetch(FetchDescriptor<Wallet>()).map(\.name) == ["Checking"])
        #expect(try context.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try context.fetch(FetchDescriptor<Transaction>()).allSatisfy { $0.wallet?.name == "Checking" })
        #expect(try context.fetchCount(FetchDescriptor<Grosh.Category>()) == categoriesBefore)
        #expect(try CategoryCatalog(context: context).categories(of: .expense).contains { $0.name == "Hobbies" })
    }

    @Test func aFileThatCantBeImportedChangesNothing() throws {
        try addExistingData()

        #expect(throws: MoneyLoverImportError.unreadableRow(line: 3)) {
            try importing(export(
                "1,10/05/2026,Café,-10.91,USD,Checking,Coffee,,,,",
                "2,10/05/2026,Café,ten,USD,Checking,Coffee,,,,"
            ))
        }

        #expect(try context.fetch(FetchDescriptor<Wallet>()).map(\.name) == ["Old wallet"])
        #expect(try context.fetchCount(FetchDescriptor<Card>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 2)
    }

    // MARK: Wallets

    @Test func eachWalletIsCreatedOnceWithAZeroStartingBalanceOnItsFirstDay() throws {
        try importing(export(
            "1,10/05/2026,Café,-10.91,USD,Checking,,,,,",
            "2,10/04/2026,Salary,1000,USD,Savings,,,,,",
            "3,09/30/2026,Café,-4.50,USD,Checking,,,,,"
        ))

        let wallets = try context.fetch(FetchDescriptor<Wallet>(sortBy: Wallet.userOrder))
        #expect(wallets.map(\.name) == ["Checking", "Savings"])
        let checking = try wallet("Checking")
        let starting = try #require(checking.transactions?.first { $0.category?.lockedRole == .startingBalance })
        #expect(starting.amountCents == 0)
        #expect(starting.isExcludedFromReport)
        #expect(starting.day == CalendarDay(year: 2026, month: 9, day: 30))
        #expect(checking.transactions?.inListOrder().last == starting)
        #expect(checking.balance(asOf: today) == Money(cents: -15_41))
        #expect(try wallet("Savings").balance(asOf: today) == Money(cents: 1_000_00))
    }
}
