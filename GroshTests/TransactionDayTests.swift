import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The Transactions tab's list: only days that have transactions, newest day first, the most recently entered
/// transaction on top within a day, and each day's net total.
@MainActor
@Suite(.namedInTheLog)
struct TransactionDayTests {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let checking: Wallet

    init() throws {
        container = try TestStore.makeContainer()
        checking = container.mainContext.addWallet("Checking")
    }

    /// Records a transaction entered `enteredAt` seconds into the test's clock.
    @discardableResult
    private func record(_ note: String, _ cents: Int, on day: CalendarDay, enteredAt seconds: Double) -> Transaction {
        context.record(cents, on: day, in: checking, note: note, enteredAt: seconds)
    }

    @Test func daysAreNewestFirstWithTheMostRecentlyEnteredTransactionOnTop() {
        let transactions = [
            record("rent", -900_00, on: day(2026, 10, 1), enteredAt: 10),
            record("coffee", -4_50, on: day(2026, 10, 3), enteredAt: 20),
            record("lunch", -12_00, on: day(2026, 10, 3), enteredAt: 40),
            record("forgot yesterday's bus", -2_75, on: day(2026, 10, 2), enteredAt: 50),
            record("tip", 5_00, on: day(2026, 10, 3), enteredAt: 30),
        ]

        let days = TransactionDay.days(of: transactions)

        #expect(days.map(\.day) == [day(2026, 10, 3), day(2026, 10, 2), day(2026, 10, 1)])
        #expect(days.map { $0.transactions.map(\.note) } == [["lunch", "tip", "coffee"], ["forgot yesterday's bus"], ["rent"]])
    }

    @Test func eachDayShowsItsNetTotalExcludedTransactionsIncluded() {
        let refund = record("refund", 20_00, on: day(2026, 10, 3), enteredAt: 3)
        refund.isExcludedFromReport = true
        let transactions = [
            record("coffee", -4_50, on: day(2026, 10, 3), enteredAt: 1),
            record("lunch", -12_00, on: day(2026, 10, 3), enteredAt: 2),
            refund,
            record("salary", 3_000_00, on: day(2026, 10, 1), enteredAt: 4),
        ]

        let days = TransactionDay.days(of: transactions)

        #expect(days.map(\.net) == [Money(cents: 3_50), Money(cents: 3_000_00)])
    }

    @Test func transactionsEnteredAtTheSameMomentKeepOneOrderWhateverOrderTheyAreFetchedIn() throws {
        let transactions = (1...6).map { record("row \($0)", -$0 * 100, on: day(2026, 10, 3), enteredAt: 0) }
        try context.save()

        let forwards = TransactionDay.days(of: transactions).flatMap(\.transactions).map(\.note)
        let backwards = TransactionDay.days(of: transactions.reversed()).flatMap(\.transactions).map(\.note)

        #expect(forwards == backwards)
    }
}

/// The order within a day survives closing and reopening the store.
@MainActor
@Suite(.namedInTheLog)
struct TransactionOrderAcrossLaunchesTests {
    private let storeURL = URL.temporaryDirectory
        .appending(path: "GroshTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "Grosh.store")

    private func openStore() throws -> ModelContainer {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let configuration = ModelConfiguration(schema: GroshStore.schema, url: storeURL, cloudKitDatabase: .none)
        return TestStore.checked(try ModelContainer(for: GroshStore.schema, configurations: configuration))
    }

    /// The notes of every transaction in list order, as the store has them now.
    private func listedNotes(in container: ModelContainer) throws -> [String] {
        let transactions = try container.mainContext.fetch(FetchDescriptor<Transaction>())
        return TransactionDay.days(of: transactions).flatMap(\.transactions).map(\.note)
    }

    @Test func theOrderWithinADayIsTheSameAfterReopeningTheStore() throws {
        let firstLaunch: [String]
        do {
            let container = try openStore()
            let wallet = Wallet(name: "Checking")
            container.mainContext.insert(wallet)
            for (index, note) in ["a", "b", "c", "d", "e", "f"].enumerated() {
                // Two entered one after the other, four at the same moment (as an import does).
                container.mainContext.record(
                    -1_00, on: day(2026, 10, 3), in: wallet, note: note, enteredAt: index < 2 ? Double(index + 1) : 0
                )
            }
            try container.mainContext.save()
            firstLaunch = try listedNotes(in: container)
        }

        let secondLaunch = try listedNotes(in: try openStore())

        #expect(firstLaunch.prefix(2) == ["b", "a"])
        #expect(secondLaunch == firstLaunch)
    }
}
