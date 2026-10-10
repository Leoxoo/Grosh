import SwiftData
import Testing
@testable import Grosh

/// Search: note text, category name and amount, across all time.
@MainActor
struct TransactionSearchTests {
    private let fixture: CategoryFixture
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.wallet }

    init() throws {
        fixture = try CategoryFixture()
    }

    @discardableResult
    private func record(
        _ cents: Int,
        _ note: String = "",
        under category: Grosh.Category? = nil,
        in wallet: Wallet? = nil,
        on day: CalendarDay = CalendarDay(year: 2026, month: 10, day: 1)
    ) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = wallet ?? checking
        transaction.category = category
        return transaction
    }

    private func search(_ text: String, in transactions: [Transaction]) -> [String] {
        transactions.matching(TransactionFilter(searchText: text)).map(\.note)
    }

    @Test func findsNoteTextWhateverItsCase() {
        let all = [record(-4_50, "Morning Coffee with Anna"), record(-12_00, "lunch")]

        #expect(search("coffee", in: all) == ["Morning Coffee with Anna"])
    }

    @Test func findsTheCategoryNameWithOrWithoutAccents() throws {
        let all = [
            record(-4_50, "flat white", under: try fixture.category("Café")),
            record(-30_00, "dinner", under: try fixture.category("Restaurants")),
            record(-2_00, "no category"),
        ]

        #expect(search("cafe", in: all) == ["flat white"])
        #expect(search("restaurant", in: all) == ["dinner"])
    }

    @Test func aWholeNumberFindsEveryAmountWithThoseDollars() {
        let all = [
            record(-973_17, "new phone"),
            record(973_00, "refund"),
            record(-97_31, "groceries"),
            record(-1_973_00, "laptop"),
            record(-9_730_00, "used car"),
        ]

        #expect(search("973", in: all) == ["new phone", "refund"])
    }

    @Test(arguments: [
        ("973.1", ["phone", "case"]),
        ("973.17", ["phone"]),
        ("$973.17", ["phone"]),
        ("-973.17", ["phone"]),
        ("973.", ["phone", "case", "charger", "refund"]),
        ("1,250", ["rent"]),
    ])
    func centsNarrowAnAmountSearch(text: String, expected: [String]) {
        let all = [
            record(-973_17, "phone"),
            record(-973_10, "case"),
            record(-973_20, "charger"),
            record(973_00, "refund"),
            record(-1_250_40, "rent"),
            record(-125_00, "gas"),
        ]

        #expect(search(text, in: all) == expected)
    }

    @Test func searchLooksAcrossAllTimeAndEveryWalletArchivedOnesIncluded() throws {
        let today = CalendarDay(year: 2026, month: 10, day: 9)
        let oldBank = Wallet(name: "Old bank")
        context.insert(oldBank)
        let brokerage = Wallet(name: "Brokerage")
        context.insert(brokerage)
        brokerage.includeInTotal = false
        let all = [
            record(-5_00, "monthly fee", in: oldBank, on: CalendarDay(year: 2021, month: 3, day: 2)),
            record(-1_00, "trading fee", in: brokerage, on: CalendarDay(year: 2026, month: 9, day: 12)),
            record(-2_00, "atm fee", on: today),
            record(-40_00, "groceries", on: today),
        ]
        try oldBank.archive()

        let listed = TransactionFilter(searchText: "fee")
            .listed(from: all, selection: .total, on: Period.month(CalendarMonth(today)).days(today: today))

        #expect(Set(listed.map(\.note)) == ["monthly fee", "trading fee", "atm fee"])
    }
}
