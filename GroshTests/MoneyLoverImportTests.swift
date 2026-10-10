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

    @Test func withEventAndExcludeFromReportAreStored() throws {
        try importing(export("1,10/05/2026,Restaurants,-42.00,USD,Checking,Dinner,Sam,Road trip,✅,"))

        let dinner = try #require(try rows(in: "Checking").first)
        #expect(dinner.withName == "Sam")
        #expect(dinner.eventName == "Road trip")
        #expect(dinner.isExcludedFromReport)
    }

    // MARK: Categories

    @Test func aRowIsFiledUnderTheCategoryOfItsNameIgnoringCase() throws {
        try importing(export(
            "1,10/05/2026,café,-3.00,USD,Checking,,,,,",
            "2,10/05/2026,PHONE BILL,-30.00,USD,Checking,,,,,"
        ))

        let filed = try rows(in: "Checking").map(\.category)
        #expect(filed.map { $0?.name } == ["Café", "Phone Bill"])
        #expect(filed.last??.parent?.name == "Bills & Utilities")
    }

    @Test func aNameUsedByAnExpenseAndAnIncomeCategoryPicksTheOneMatchingTheAmountsSign() throws {
        let catalog = CategoryCatalog(context: context)
        let spent = try catalog.add(CategoryDraft(name: "Refunds", type: .expense))
        let received = try catalog.add(CategoryDraft(name: "Refunds", type: .income))

        try importing(export(
            "1,10/05/2026,Refunds,-3.00,USD,Checking,,,,,",
            "2,10/05/2026,Refunds,8.00,USD,Checking,,,,,"
        ))

        #expect(try rows(in: "Checking").map(\.category) == [spent, received])
    }

    @Test func anUnknownCategoryBecomesATopLevelCategoryTypedByTheAmountsSign() throws {
        let before = try context.fetchCount(FetchDescriptor<Grosh.Category>())

        try importing(export(
            "1,10/05/2026,Lottery,25.00,USD,Checking,,,,,",
            "2,10/04/2026,Lottery,-2.00,USD,Checking,,,,,",
            "3,10/03/2026,Garden,-12.00,USD,Checking,,,,,"
        ))

        let filed = try rows(in: "Checking").map(\.category)
        let lottery = try #require(filed[0])
        let garden = try #require(filed[2])
        #expect(filed[1] == lottery)
        #expect((lottery.name, lottery.type, lottery.parent) == ("Lottery", .income, nil))
        #expect((garden.name, garden.type, garden.parent) == ("Garden", .expense, nil))
        #expect(try context.fetchCount(FetchDescriptor<Grosh.Category>()) == before + 2)
    }

    // MARK: Cards

    private func cards() throws -> [Card] {
        try context.fetch(FetchDescriptor<Card>(sortBy: Card.userOrder))
    }

    @Test func aCardHashtagBecomesTheRowsCardPaidFromCheckingAndLeavesTheNote() throws {
        try importing(export(
            "1,10/05/2026,Products,-20.00,USD,Checking (Navy Federal),Groceries #chase ,,,,",
            "2,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),#checking Coffee,,,,",
            "3,10/05/2026,Salary,900,USD,Saving (Apple),Pay,,,,"
        ))

        let checking = try wallet("Checking (Navy Federal)")
        let imported = try rows(in: "Checking (Navy Federal)")
        #expect(imported.map(\.note) == ["Groceries", "Coffee"])
        #expect(imported.map { $0.card?.name } == ["Chase", "Navy Federal Debit"])
        #expect(try cards().map(\.name) == ["Navy Federal Debit", "Chase"])
        #expect(try cards().map(\.kind) == [.debit, .credit])
        #expect(try cards().allSatisfy { $0.payingWallet == checking })
    }

    @Test func cardHashtagsAreFoundInAnyCaseAndAnywhereInTheNote() throws {
        try importing(export("1,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),Lunch #BoA downtown,,,,"))

        let lunch = try #require(try rows(in: "Checking (Navy Federal)").first)
        #expect(lunch.card?.name == "Bank of America")
        #expect(lunch.note == "Lunch downtown")
    }

    @Test func theFirstCardHashtagWinsAndEveryOtherHashtagStays() throws {
        try importing(export("1,10/05/2026,Travel,-90.00,USD,Checking (Navy Federal),Hotel #trip #citi #amex,,,,"))

        let hotel = try #require(try rows(in: "Checking (Navy Federal)").first)
        #expect(hotel.card?.name == "Citi")
        #expect(hotel.note == "Hotel #trip #amex")
        #expect(try cards().map(\.name) == ["Citi"])
    }

    @Test func aRowWithoutACardHashtagGetsNoCard() throws {
        try importing(export(
            "1,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),Coffee #chasefreedom,,,,",
            "2,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),Coffee,,,,"
        ))

        #expect(try rows(in: "Checking (Navy Federal)").allSatisfy { $0.card == nil })
        #expect(try rows(in: "Checking (Navy Federal)").first?.note == "Coffee #chasefreedom")
        #expect(try cards().isEmpty)
    }

    @Test func withoutACheckingWalletACardIsPaidFromTheWalletOfItsFirstRow() throws {
        try importing(export("1,10/05/2026,Café,-3.00,USD,Cash,Coffee #paypal,,,,"))

        #expect(try cards().map(\.payingWallet) == [try wallet("Cash")])
    }

    @Test func aTransferRowGetsNoCardAndKeepsItsHashtagLinkedOrNot() throws {
        try importing(export(
            "1,10/05/2026,Outgoing transfer,-250,USD,Checking (Navy Federal),To savings #chase,,,✅,",
            "2,10/05/2026,Incoming transfer,250,USD,Saving (Apple),To savings #chase,,,✅,",
            "3,10/04/2026,Outgoing transfer,-30,USD,Checking (Navy Federal),Sent out #citi,,,✅,"
        ))

        let checking = try rows(in: "Checking (Navy Federal)")
        #expect(checking.map(\.isBalanceAdjustment) == [false, true])
        #expect(checking.allSatisfy { $0.card == nil })
        #expect(checking.map(\.note) == ["To savings #chase", "Sent out #citi"])
        #expect(try cards().isEmpty)
    }

    @Test func aRowOutsideItsCardsPayingWalletGetsNoCardAndKeepsItsHashtag() throws {
        try importing(export(
            "1,10/05/2026,Café,-3.00,USD,Cash,Coffee #chase,,,,",
            "2,10/05/2026,Products,-20.00,USD,Checking (Navy Federal),Groceries #citi,,,,"
        ))

        let coffee = try #require(try rows(in: "Cash").first)
        #expect(coffee.card == nil)
        #expect(coffee.note == "Coffee #chase")
        #expect(try cards().map(\.name) == ["Citi"])
    }

    @Test func withoutACheckingWalletACardIsOnlyGivenInTheWalletOfItsFirstRowThatCanHaveOne() throws {
        try importing(export(
            "1,10/06/2026,Outgoing transfer,-5,USD,Savings,Moved #paypal,,,✅,",
            "2,10/05/2026,Café,-3.00,USD,Cash,Coffee #paypal,,,,",
            "3,10/04/2026,Café,-4.00,USD,Savings,Tea #paypal,,,,"
        ))

        #expect(try cards().map(\.payingWallet) == [try wallet("Cash")])
        #expect(try rows(in: "Cash").map { $0.card?.name } == ["PayPal"])
        #expect(try rows(in: "Savings").allSatisfy { $0.card == nil })
        #expect(try rows(in: "Savings").map(\.note) == ["Moved #paypal", "Tea #paypal"])
    }

    // MARK: Transfers

    private func transferRows(in name: String) throws -> [Transaction] {
        try rows(in: name).filter { $0.category?.isTransferHalf == true }
    }

    @Test func outgoingAndIncomingTransferRowsOnOneDayWithOppositeAmountsBecomeALinkedTransfer() throws {
        try importing(export(
            "1,10/05/2026,Incoming transfer,250,USD,Savings,To savings,,,✅,",
            "2,10/05/2026,Outgoing transfer,-250,USD,Checking,To savings,,,✅,"
        ))

        let outgoing = try #require(try transferRows(in: "Checking").first)
        let incoming = try #require(try transferRows(in: "Savings").first)
        #expect(try outgoing.otherHalf(in: context) == incoming)
        #expect(try incoming.otherHalf(in: context) == outgoing)
        let wallets = try incoming.transferWallets(in: context)
        #expect(wallets.from == (try wallet("Checking")))
        #expect(wallets.to == (try wallet("Savings")))
        #expect(!outgoing.isBalanceAdjustment && !incoming.isBalanceAdjustment)
    }

    @Test func transferRowsPairOneToOneOnlyOnTheSameDayInAnotherWallet() throws {
        try importing(export(
            "1,10/05/2026,Outgoing transfer,-100,USD,Checking,,,,,",
            "2,10/05/2026,Incoming transfer,100,USD,Checking,,,,,",
            "3,10/05/2026,Outgoing transfer,-100,USD,Checking,,,,,",
            "4,10/05/2026,Incoming transfer,100,USD,Savings,,,,,",
            "5,10/04/2026,Incoming transfer,100,USD,Savings,,,,,",
            "6,10/03/2026,Outgoing transfer,-100,USD,Checking,,,,,",
            "7,10/03/2026,Incoming transfer,99,USD,Savings,,,,,"
        ))

        let checking = try rows(in: "Checking")
        let savings = try rows(in: "Savings")
        #expect(try checking[0].otherHalf(in: context) == savings[0])
        #expect(checking.filter { $0.linkID != nil }.count == 1)
        #expect(savings.filter { $0.linkID != nil }.count == 1)
    }

    @Test func aTransferRowWithNoPartnerBecomesABalanceAdjustmentThatKeepsItsExcludedFlag() throws {
        try importing(export(
            "1,10/05/2026,Outgoing transfer,-30,USD,Checking,Sent out,,,✅,",
            "2,10/04/2026,Incoming transfer,45.50,USD,Checking,Came in,,,,"
        ))

        let adjustments = try rows(in: "Checking")
        #expect(adjustments.allSatisfy { $0.isBalanceAdjustment && $0.linkID == nil })
        #expect(adjustments.map { $0.category?.lockedRole } == [.otherExpense, .otherIncome])
        #expect(adjustments.map(\.amountCents) == [-30_00, 45_50])
        #expect(adjustments.map(\.isExcludedFromReport) == [true, false])
        #expect(adjustments.map(\.note) == ["Sent out", "Came in"])
    }

    // MARK: Debts and loans

    /// Each Loan or Debt in the store as `wallet day amount`, open or settled.
    private func debtsAndLoans() throws -> (open: Set<String>, settled: Set<String>) {
        func describe(_ loanOrDebt: LoanOrDebt) -> String {
            let original = loanOrDebt.original
            return "\(original.wallet?.name ?? "") \(original.day.month)/\(original.day.day) \(original.amountCents)"
        }
        let all = try DebtsAndLoans(in: context)
        return (Set(all.open.map(describe)), Set(all.settled.map(describe)))
    }

    @Test func eachDebtCollectionSettlesTheEarliestOpenLoanOfItsWalletAndAmount() throws {
        try importing(export(
            "1,09/25/2026,Debt Collection,50,USD,Cash,,Sam,,✅,",
            "2,09/20/2026,Debt Collection,100,USD,Cash,,Sam,,✅,",
            "3,09/10/2026,Loan,-100,USD,Cash,,Sam,,✅,",
            "4,09/05/2026,Loan,-50,USD,Cash,,Alex,,✅,",
            "5,09/02/2026,Loan,-100,USD,Checking,,Sam,,✅,",
            "6,09/01/2026,Loan,-100,USD,Cash,,Kim,,✅,"
        ))

        let loans = try debtsAndLoans()
        #expect(loans.settled == ["Cash 9/1 -10000", "Cash 9/5 -5000"])
        #expect(loans.open == ["Cash 9/10 -10000", "Checking 9/2 -10000"])
        let collection = try #require(try rows(in: "Cash").first { $0.amountCents == 100_00 })
        #expect(try collection.related(in: context).map(\.day) == [CalendarDay(year: 2026, month: 9, day: 1)])
    }

    @Test func aDebtCollectionNeverSettlesALoanMadeAfterIt() throws {
        try importing(export(
            "1,09/20/2026,Loan,-100,USD,Cash,,Sam,,✅,",
            "2,09/10/2026,Debt Collection,100,USD,Cash,,Sam,,✅,"
        ))

        #expect(try debtsAndLoans().open == ["Cash 9/20 -10000"])
        #expect(try rows(in: "Cash").allSatisfy { $0.linkID == nil })
    }

    @Test func eachRepaymentSettlesTheEarliestOpenDebtOfItsWalletAndAmount() throws {
        try importing(export(
            "1,09/20/2026,Repayment,-300,USD,Checking,,Bank,,✅,",
            "2,09/10/2026,Debt,300,USD,Checking,,Bank,,✅,",
            "3,09/01/2026,Debt,300,USD,Checking,,Bank,,✅,"
        ))

        let debts = try debtsAndLoans()
        #expect(debts.settled == ["Checking 9/1 30000"])
        #expect(debts.open == ["Checking 9/10 30000"])
    }

    // MARK: Summary

    @Test func theSummaryCountsEachWalletsRowsTheCardsCreatedAndTheUnmatchedRows() throws {
        let summary = try importing(export(
            "1,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),Coffee #chase,,,,",
            "2,10/05/2026,Products,-20.00,USD,Checking (Navy Federal),Groceries #citi,,,,",
            "3,10/04/2026,Outgoing transfer,-40,USD,Checking (Navy Federal),,,,✅,",
            "4,10/04/2026,Café,-2.50,USD,Cash,Tea #chase,,,,",
            "5,10/03/2026,Debt Collection,25,USD,Cash,,Sam,,✅,",
            "6,10/02/2026,Outgoing transfer,-60,USD,Checking (Navy Federal),,,,✅,",
            "7,10/02/2026,Incoming transfer,60,USD,Cash,,,,✅,"
        ))

        #expect(summary.wallets == [
            MoneyLoverImportSummary.WalletCount(name: "Checking (Navy Federal)", transactionCount: 4),
            MoneyLoverImportSummary.WalletCount(name: "Cash", transactionCount: 3),
        ])
        #expect(summary.cardsCreated == 2)
        #expect(summary.unmatchedRows == [
            MoneyLoverImportSummary.UnmatchedRow(
                line: 4, day: CalendarDay(year: 2026, month: 10, day: 4), categoryName: "Outgoing transfer",
                amount: Money(cents: -40_00), walletName: "Checking (Navy Federal)", outcome: .balanceAdjustment
            ),
            MoneyLoverImportSummary.UnmatchedRow(
                line: 6, day: CalendarDay(year: 2026, month: 10, day: 3), categoryName: "Debt Collection",
                amount: Money(cents: 25_00), walletName: "Cash", outcome: .unlinkedPayment
            ),
        ])
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
        #expect(try context.otherCategory(.expense).transactions?.isEmpty == true)
        #expect(try context.lockedCategory(.startingBalance).transactions?.map { $0.wallet?.name } == ["Checking"])
    }

    /// Every transaction in list order, described by what the user sees of it.
    private func everything() throws -> [String] {
        try context.fetch(FetchDescriptor<Transaction>()).inListOrder().map { transaction in
            let related = (try? transaction.related(in: context).map(\.amountCents)) ?? []
            return [
                transaction.wallet?.name ?? "", "\(transaction.dayRaw)", "\(transaction.amountCents)",
                transaction.category?.name ?? "", transaction.note, transaction.card?.name ?? "",
                transaction.withName, transaction.eventName, "\(transaction.isExcludedFromReport)",
                "\(transaction.isBalanceAdjustment)", "\(related)",
            ].joined(separator: "|")
        }
    }

    @Test func importingTheSameFileAgainGivesTheSameResult() throws {
        let file = export(
            "1,10/05/2026,Lottery,25.00,USD,Checking (Navy Federal),Ticket #citi,,,,",
            "2,10/05/2026,Café,-3.00,USD,Checking (Navy Federal),Coffee #chase,Sam,Trip,,",
            "3,10/04/2026,Outgoing transfer,-40,USD,Checking (Navy Federal),,,,✅,",
            "4,10/04/2026,Incoming transfer,40,USD,Cash,,,,✅,",
            "5,10/03/2026,Incoming transfer,15,USD,Cash,,,,✅,",
            "6,10/02/2026,Debt Collection,25,USD,Cash,,Sam,,✅,",
            "7,10/01/2026,Loan,-25,USD,Cash,,Sam,,✅,",
            "8,09/30/2026,Loan,-10,USD,Cash,,Kim,,✅,"
        )
        let firstSummary = try importing(file)
        let firstResult = try everything()
        let categories = try context.fetchCount(FetchDescriptor<Grosh.Category>())

        let secondSummary = try importing(file)

        #expect(secondSummary == firstSummary)
        #expect(try everything() == firstResult)
        #expect(try context.fetchCount(FetchDescriptor<Grosh.Category>()) == categories)
        #expect(try context.fetch(FetchDescriptor<Card>()).map(\.name).sorted() == ["Chase", "Citi"])
        #expect(try context.fetchCount(FetchDescriptor<Wallet>()) == 2)
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

    @Test func withinADayRowsKeepTheFilesOrderAndWhatIsEnteredLaterGoesOnTop() throws {
        try importing(export(
            "1,10/05/2026,Café,-1.00,USD,Checking,First,,,,",
            "2,10/05/2026,Café,-2.00,USD,Checking,Second,,,,",
            "3,10/04/2026,Café,-3.00,USD,Checking,Older,,,,",
            "4,10/05/2026,Café,-4.00,USD,Checking,Third,,,,"
        ))
        var later = TransactionDraft(type: .expense, day: CalendarDay(year: 2026, month: 10, day: 5))
        later.wallet = try wallet("Checking")
        later.amount = Money(cents: 5_00)
        later.category = try context.otherCategory(.expense)
        later.note = "Added later"
        try Transaction.create(later, in: context)

        #expect(try rows(in: "Checking").map(\.note) == ["Added later", "First", "Second", "Third", "Older"])
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
