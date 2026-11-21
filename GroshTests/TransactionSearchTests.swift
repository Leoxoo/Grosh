import SwiftData
import Testing
@testable import Grosh

/// Search: note text, category name, Card name and amount, across all time.
@MainActor
@Suite(.namedInTheLog)
struct TransactionSearchTests {
    private let fixture: TestStore
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.checking }

    init() throws {
        fixture = try TestStore()
    }

    @discardableResult
    private func record(
        _ cents: Int,
        _ note: String = "",
        under category: Grosh.Category? = nil,
        in wallet: Wallet? = nil,
        on day: CalendarDay = CalendarDay(year: 2026, month: 10, day: 1)
    ) -> Transaction {
        context.record(cents, on: day, in: wallet ?? checking, under: category, note: note)
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

    @Test func findsEveryTransactionPaidWithACardByItsName() throws {
        let chase = try context.addCard("Chase Freedom", paidFrom: checking)
        let paid = [record(-4_50, "flat white"), record(-30_00, "dinner")]
        for transaction in paid {
            transaction.card = chase
        }
        let all = paid + [record(-2_00, "cash")]

        #expect(search("chase", in: all) == ["flat white", "dinner"])
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
        let today = TestStore.today
        let oldBank = context.addWallet("Old bank")
        let brokerage = context.addWallet("Brokerage", includeInTotal: false)
        let all = [
            record(-5_00, "monthly fee", in: oldBank, on: CalendarDay(year: 2021, month: 3, day: 2)),
            record(-1_00, "trading fee", in: brokerage, on: CalendarDay(year: 2026, month: 9, day: 12)),
            record(-2_00, "atm fee", on: today),
            record(-40_00, "groceries", on: today),
        ]
        try oldBank.archive(today: today)

        let listed = TransactionListing(
            all, showing: .total, on: Period.month(CalendarMonth(today)).days(today: today),
            filter: TransactionFilter(searchText: "fee")
        ).transactions

        #expect(Set(listed.map(\.note)) == ["monthly fee", "trading fee", "atm fee"])
    }

    // MARK: Pickers

    @Test func aPickerListsItsCandidatesNewestFirstNarrowedBySearch() {
        let older = record(-4_50, "coffee", on: CalendarDay(year: 2026, month: 9, day: 1))
        let newer = record(-3_00, "coffee", on: CalendarDay(year: 2026, month: 10, day: 2))
        let lunch = record(-12_00, "lunch")
        let candidates = PickerCandidates([older, lunch, newer])

        #expect(candidates.transactions == [newer, lunch, older])
        let listing = TransactionListing.picking(candidates, filter: TransactionFilter(searchText: "coffee"))
        #expect(listing.transactions == [newer, older])
    }

    @Test func aPickersRowsShowTheirWalletOnlyWhenTheCandidatesComeFromMoreThanOne() {
        let cash = context.addWallet("Cash")
        let inChecking = [record(-4_50, "coffee"), record(-12_00, "lunch")]
        let inBoth = inChecking + [record(-2_00, "bus", in: cash)]

        #expect(!TransactionListing.picking(PickerCandidates(inChecking), filter: TransactionFilter()).mixesWallets)
        #expect(TransactionListing.picking(PickerCandidates(inBoth), filter: TransactionFilter()).mixesWallets)
        #expect(!TransactionListing.picking(PickerCandidates(inBoth), filter: TransactionFilter(wallet: cash)).mixesWallets)
    }
}
