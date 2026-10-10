import SwiftData
import Testing
@testable import Grosh

/// Filters: wallet, category (with its subcategories), Card, type, date range, amount range and excluded only.
/// They combine with each other and with the selected period.
@MainActor
struct TransactionFilterTests {
    private let fixture: CategoryFixture
    private var context: ModelContext { fixture.context }
    private var checking: Wallet { fixture.wallet }
    private let today = CalendarDay(year: 2026, month: 10, day: 9)

    init() throws {
        fixture = try CategoryFixture()
    }

    private func day(_ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: 2026, month: month, day: day)
    }

    private func month(_ month: Int) -> DayRange {
        Period.month(CalendarMonth(year: 2026, month: month)).days(today: today)
    }

    private func card(_ name: String) -> Card {
        let card = Card(name: name, kind: .credit, payingWallet: nil)
        context.insert(card)
        card.payingWallet = checking
        return card
    }

    @discardableResult
    private func record(
        _ cents: Int,
        _ note: String,
        on day: CalendarDay? = nil,
        under category: Grosh.Category? = nil,
        card: Card? = nil,
        in wallet: Wallet? = nil,
        excludedFromReport: Bool = false
    ) -> Transaction {
        let transaction = Transaction(amount: Money(cents: cents), day: day ?? self.day(10, 1), wallet: nil, category: nil, note: note)
        context.insert(transaction)
        transaction.wallet = wallet ?? checking
        transaction.category = category
        transaction.card = card
        transaction.isExcludedFromReport = excludedFromReport
        return transaction
    }

    private func notes(_ filter: TransactionFilter, in all: [Transaction], on days: DayRange = DayRange()) -> Set<String> {
        Set(filter.listed(from: all, selection: .total, on: days).map(\.note))
    }

    @Test func aCardFilterListsThatCardsTransactionsInTheSelectedPeriodAndTheirTotal() {
        let amex = card("Amex")
        let chase = card("Chase")
        let all = [
            record(-40_00, "groceries", on: day(9, 3), card: amex),
            record(-12_50, "lunch", on: day(9, 20), card: amex),
            record(5_00, "cashback", on: day(9, 28), card: amex, excludedFromReport: true),
            record(-99_00, "shoes", on: day(9, 5), card: chase),
            record(-7_00, "coffee", on: day(10, 2), card: amex),
            record(-1_00, "cash tip", on: day(9, 6)),
        ]

        let listed = TransactionFilter(card: amex).listed(from: all, selection: .total, on: month(9))

        #expect(Set(listed.map(\.note)) == ["groceries", "lunch", "cashback"])
        #expect(listed.net == Money(cents: -47_50))
    }

    @Test func aParentCategoryFilterIncludesItsSubcategories() throws {
        let food = try fixture.category("Food & Beverage")
        let all = [
            record(-30_00, "dinner", under: try fixture.category("Restaurants")),
            record(-4_50, "latte", under: try fixture.category("Café")),
            record(-8_00, "food truck", under: food),
            record(-60_00, "groceries", under: try fixture.category("Products")),
            record(-2_00, "uncategorized"),
        ]

        #expect(notes(TransactionFilter(category: food), in: all) == ["dinner", "latte", "food truck"])
        #expect(notes(TransactionFilter(category: try fixture.category("Café")), in: all) == ["latte"])
    }

    @Test func aWalletFilterListsOnlyThatWalletsTransactionsArchivedWalletsIncludedInSearch() throws {
        let cash = Wallet(name: "Cash")
        context.insert(cash)
        let oldBank = Wallet(name: "Old bank")
        context.insert(oldBank)
        let all = [
            record(-3_00, "atm fee"),
            record(-5_00, "bus fare", in: cash),
            record(-1_00, "cash fee", in: cash),
            record(-9_00, "closing fee", in: oldBank),
        ]
        try oldBank.archive()

        #expect(notes(TransactionFilter(wallet: cash), in: all) == ["bus fare", "cash fee"])
        #expect(notes(TransactionFilter(searchText: "fee", wallet: oldBank), in: all) == ["closing fee"])
    }

    @Test func aWalletFilterListsAnArchivedOrLeftOutWalletInTheSelectedPeriodWithoutSearching() throws {
        let oldBank = Wallet(name: "Old bank")
        context.insert(oldBank)
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        savings.includeInTotal = false
        let all = [
            record(-3_00, "atm fee", on: day(9, 2)),
            record(-9_00, "closing fee", on: day(9, 4), in: oldBank),
            record(-8_00, "older fee", on: day(8, 4), in: oldBank),
            record(50_00, "interest", on: day(9, 30), in: savings),
        ]
        try oldBank.archive()

        #expect(TransactionFilter(wallet: oldBank).listed(from: all, selection: .total, on: month(9)).map(\.note)
            == ["closing fee"])
        #expect(TransactionFilter(wallet: savings).listed(from: all, selection: .wallet(checking), on: month(9))
            .map(\.note) == ["interest"])
    }

    @Test func theStripReachesBackToTheFilteredWalletsFirstTransaction() throws {
        let oldBank = Wallet(name: "Old bank")
        context.insert(oldBank)
        let all = [
            record(-3_00, "atm fee", on: day(9, 2)),
            record(-9_00, "closing fee", on: CalendarDay(year: 2025, month: 11, day: 4), in: oldBank),
        ]
        try oldBank.archive()

        let filtered = TransactionFilter(wallet: oldBank).transactions(in: .total, from: all)
        let strip = TimeRange.month.periods(from: filtered.firstDay, today: today)

        #expect(filtered.map(\.note) == ["closing fee"])
        #expect(strip.first == .month(CalendarMonth(year: 2025, month: 11)))
        #expect(TransactionFilter().transactions(in: .total, from: all).map(\.note) == ["atm fee"])
    }

    @Test func aTypeFilterListsOnlyTransactionsOfThatCategoryType() throws {
        let all = [
            record(-30_00, "dinner", under: try fixture.category("Restaurants")),
            record(3_000_00, "paycheck", under: try fixture.category("Salary", .income)),
            record(-100_00, "lent to Pasha", under: try fixture.category("Loan", .debtLoan)),
        ]

        #expect(notes(TransactionFilter(type: .income), in: all) == ["paycheck"])
        #expect(notes(TransactionFilter(type: .debtLoan), in: all) == ["lent to Pasha"])
    }

    @Test func aDateRangeIncludesBothEndsAndMayBeOpenOnEitherSide() {
        let all = [
            record(-1_00, "before", on: day(9, 9)),
            record(-2_00, "first day", on: day(9, 10)),
            record(-3_00, "last day", on: day(9, 20)),
            record(-4_00, "after", on: day(9, 21)),
        ]

        #expect(notes(TransactionFilter(dateRange: DayRange(first: day(9, 10), last: day(9, 20))), in: all) == ["first day", "last day"])
        #expect(notes(TransactionFilter(dateRange: DayRange(first: day(9, 21))), in: all) == ["after"])
        #expect(notes(TransactionFilter(dateRange: DayRange(last: day(9, 9))), in: all) == ["before"])
    }

    @Test func anAmountRangeComparesAmountsAsEnteredBothEndsIncluded() {
        let all = [
            record(-49_99, "under"),
            record(-50_00, "lowest"),
            record(75_00, "refund"),
            record(-100_00, "highest"),
            record(-100_01, "over"),
        ]

        #expect(notes(TransactionFilter(minimumAmount: Money(cents: 50_00), maximumAmount: Money(cents: 100_00)), in: all)
            == ["lowest", "refund", "highest"])
        #expect(notes(TransactionFilter(minimumAmount: Money(cents: 100_00)), in: all) == ["highest", "over"])
        #expect(notes(TransactionFilter(maximumAmount: Money(cents: 50_00)), in: all) == ["under", "lowest"])
    }

    @Test func excludedOnlyListsTransactionsExcludedFromReport() {
        let all = [
            record(-30_00, "dinner"),
            record(500_00, "reimbursement", excludedFromReport: true),
        ]

        #expect(notes(TransactionFilter(excludedOnly: true), in: all) == ["reimbursement"])
    }

    @Test func filtersCombineWithEachOtherWithTheSelectedWalletAndWithTheSelectedPeriod() throws {
        let amex = card("Amex")
        let cash = Wallet(name: "Cash")
        context.insert(cash)
        let restaurants = try fixture.category("Restaurants")
        let all = [
            record(-30_00, "dinner", on: day(9, 12), under: restaurants, card: amex),
            record(-30_00, "other card", on: day(9, 12), under: restaurants),
            record(-30_00, "other category", on: day(9, 12), under: try fixture.category("Café"), card: amex),
            record(-300_00, "too much", on: day(9, 12), under: restaurants, card: amex),
            record(-30_00, "last month", on: day(8, 12), under: restaurants, card: amex),
            record(-30_00, "other wallet", on: day(9, 12), under: restaurants, in: cash),
        ]
        let filter = TransactionFilter(category: restaurants, card: amex, maximumAmount: Money(cents: 100_00))

        let listed = filter.listed(from: all, selection: .wallet(checking), on: month(9))

        #expect(listed.map(\.note) == ["dinner"])
    }

    @Test func searchCombinesWithTheFilters() {
        let amex = card("Amex")
        let all = [
            record(-4_50, "coffee", card: amex),
            record(-4_50, "coffee beans"),
            record(-12_00, "lunch", card: amex),
        ]

        #expect(notes(TransactionFilter(searchText: "coffee", card: amex), in: all) == ["coffee"])
    }

    @Test func aFilterIsOnWhenItHasSearchTextOrAnyFilterSet() {
        #expect(!TransactionFilter().isOn)
        #expect(!TransactionFilter(searchText: "  ").isOn)
        #expect(TransactionFilter(searchText: "973").isOn)
        #expect(TransactionFilter(card: card("Amex")).isOn)
        #expect(TransactionFilter(dateRange: DayRange(first: day(9, 1))).isOn)
        #expect(TransactionFilter(minimumAmount: Money(cents: 0)).isOn)
        #expect(TransactionFilter(excludedOnly: true).isOn)
    }
}
