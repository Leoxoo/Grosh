import Foundation
import SwiftData
import Testing
@testable import Grosh

/// The dotted line of Home's Spent and Income cards: what the Recurring transactions still have due from today to the
/// end of the current month, Expected by month end, and the popup on a day still to come.
@MainActor
struct MonthGraphProjectionTests {
    private let store: CategoryFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.wallet }
    /// The 12th of a 31-day month.
    private let today = day(2026, 10, 12)

    init() throws {
        store = try CategoryFixture()
    }

    /// Records `cents` (signed, as it moves the wallet) filed under `categoryName` on `day`, in Checking.
    private func record(
        _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense, on day: CalendarDay
    ) throws {
        let transaction = Transaction(amount: Money(cents: cents), day: day, wallet: nil, category: nil)
        context.insert(transaction)
        transaction.wallet = checking
        transaction.category = try store.category(categoryName, type)
    }

    /// A Recurring transaction named `name` of `cents`, entered positive, filed under `categoryName`, paid from
    /// Checking unless another wallet is given, repeating `preset` from `start` until `end`, with any changes
    /// `configure` makes, and saved on `today`. Occurrences on or before today are skipped when it is saved.
    @discardableResult
    private func schedule(
        _ name: String, _ cents: Int, _ categoryName: String, _ type: CategoryType = .expense,
        starting start: CalendarDay, preset: RepeatPreset = .monthly, end: RepeatEnd = .forever,
        wallet: Wallet? = nil, configure: (inout RecurringDraft) -> Void = { _ in }
    ) throws -> RecurringTransaction {
        var draft = RecurringDraft(startDay: start)
        draft.name = name
        draft.amount = Money(cents: cents)
        draft.type = type
        draft.wallet = wallet ?? checking
        draft.category = try store.category(categoryName, type)
        draft.preset = preset
        switch end {
        case .forever:
            draft.endKind = .forever
        case .until(let last):
            draft.endKind = .until
            draft.untilDay = last
        case .afterCount(let count):
            draft.endKind = .afterCount
            draft.occurrenceCount = count
        }
        configure(&draft)
        return try RecurringTransaction.create(draft, today: today, in: context)
    }

    /// The card for `side` showing `month`, this month unless another is given, made from every transaction and every
    /// Recurring transaction in the store, those in Recently Deleted included.
    private func graph(_ side: SpentOrIncome, in month: CalendarMonth? = nil) throws -> MonthGraph {
        let transactions = try context.fetch(FetchDescriptor<Transaction>())
        let recurring = try context.fetch(FetchDescriptor<RecurringTransaction>())
        return MonthGraph(side, of: transactions, recurring: recurring, in: month ?? CalendarMonth(today), today: today)
    }

    // MARK: What the dotted line adds

    /// Weekly from October 5: the 5th and the 12th were skipped when it was saved today, so the 19th and the 26th are
    /// left. Future lists only the 19th.
    @Test func theDottedLineStepsUpOnEveryOccurrenceLeftOfAScheduleThatRepeatsForever() throws {
        try record(-40_00, "Café", on: day(2026, 10, 3))
        let lunches = try schedule("Lunch club", 10_00, "Restaurants", starting: day(2026, 10, 5), preset: .weekly)

        let spent = try graph(.spent)
        let dotted = try #require(spent.scheduledLine)

        #expect(lunches.scheduledDays(today: today) == [day(2026, 10, 19)])
        #expect(dotted.map(\.position) == (12...31).map { Double($0) / 31 })
        #expect(dotted.map(\.total.cents) ==
            Array(repeating: 40_00, count: 7) + Array(repeating: 50_00, count: 7) + Array(repeating: 60_00, count: 6))
        #expect(dotted.first?.position == spent.line.last?.position)
        #expect(spent.expectedByMonthEnd == Money(cents: 60_00))
    }

    /// Daily from October 1 for fifteen days: the first twelve were skipped when it was saved today, so three are left.
    /// Weekly from October 13 until the 24th: the 13th and the 20th, not the 27th.
    @Test func anEndingScheduleAddsOnlyThePaymentsItHasLeft() throws {
        try schedule("Parking", 2_00, "Parking Fees", starting: day(2026, 10, 1), preset: .daily, end: .afterCount(15))
        try schedule(
            "Cleaner", 20_00, "Home Improvement", starting: day(2026, 10, 13), preset: .weekly,
            end: .until(day(2026, 10, 24))
        )

        let spent = try graph(.spent)

        #expect(spent.popup(on: day(2026, 10, 15)).scheduled.map(\.name) == ["Parking"])
        #expect(spent.popup(on: day(2026, 10, 16)).scheduled.isEmpty)
        #expect(spent.popup(on: day(2026, 10, 27)).scheduled.isEmpty)
        #expect(spent.expectedByMonthEnd == Money(cents: 46_00))
    }

    /// Two Electricity Bills averaging 60.00 were paid in September, so the Bill's transactions start at 60.00, not at
    /// the 55.00 it was saved with.
    @Test func aVaryingBillAddsItsEstimatedAmount() throws {
        try record(-50_00, "Electricity Bill", on: day(2026, 9, 3))
        try record(-70_00, "Electricity Bill", on: day(2026, 9, 28))
        try schedule("Electricity", 55_00, "Electricity Bill", starting: day(2026, 10, 20)) { draft in
            draft.kind = .bill
            draft.amountVaries = true
        }

        let spent = try graph(.spent)

        #expect(spent.popup(on: day(2026, 10, 20)).scheduled == [
            MonthGraphProjection.Item(name: "Electricity", day: day(2026, 10, 20), amount: Money(cents: 60_00)),
        ])
        #expect(spent.expectedByMonthEnd == Money(cents: 60_00))
    }

    // MARK: What adds nothing

    @Test func aDeletedScheduleAddsNothing() throws {
        let gym = try schedule("Gym", 30_00, "Sports", starting: day(2026, 10, 20))
        #expect(try graph(.spent).expectedByMonthEnd == Money(cents: 30_00))

        try gym.delete(today: today, in: context)

        let spent = try graph(.spent)
        #expect(spent.scheduledLine == nil)
        #expect(spent.expectedByMonthEnd == nil)
        #expect(spent.popup(on: day(2026, 10, 20)).scheduled.isEmpty)
    }

    /// A schedule in an archived wallet is paused. A wallet left out of the Total doesn't count on the cards either.
    @Test func aScheduleInAnArchivedOrDeletedWalletOrOneOutsideTheTotalAddsNothing() throws {
        let oldBank = Wallet(name: "Old bank")
        let cash = Wallet(name: "Cash")
        let savings = Wallet(name: "Savings")
        savings.includeInTotal = false
        for wallet in [oldBank, cash, savings] {
            context.insert(wallet)
        }
        try schedule("Rent", 900_00, "Rentals", starting: day(2026, 10, 15), wallet: oldBank)
        try schedule("Tips", 20_00, "Tips", .income, starting: day(2026, 10, 16), wallet: cash)
        try schedule("Interest", 5_00, "Collect Interest", .income, starting: day(2026, 10, 17), wallet: savings)
        #expect(try graph(.spent).expectedByMonthEnd == Money(cents: 900_00))
        #expect(try graph(.income).expectedByMonthEnd == Money(cents: 20_00))

        oldBank.isArchived = true
        cash.deletedAt = Date.now

        for side in SpentOrIncome.allCases {
            let card = try graph(side)
            #expect(card.scheduledLine == nil)
            #expect(card.expectedByMonthEnd == nil)
        }
    }

    /// Weekly from October 31: the month's last day counts, November 7 doesn't. One starting November 1 adds nothing.
    @Test func occurrencesAfterTheMonthsLastDayAddNothing() throws {
        try schedule("Cinema", 12_00, "Movies", starting: day(2026, 10, 31), preset: .weekly)
        try schedule("Insurance", 80_00, "Car Insurance", starting: day(2026, 11, 1))

        let spent = try graph(.spent)

        #expect(spent.popup(on: day(2026, 10, 31)).scheduled.map(\.name) == ["Cinema"])
        #expect(spent.scheduledLine?.last?.position == 1)
        #expect(spent.expectedByMonthEnd == Money(cents: 12_00))
    }

    // MARK: Expected by month end

    /// The Loan's schedule is filed under a Debt/Loan category, so it counts on neither card.
    @Test func expectedByMonthEndIsTodaysTotalPlusWhatIsScheduledForTheCard() throws {
        try record(-40_00, "Café", on: day(2026, 10, 3))
        try record(1_000_00, "Salary", .income, on: day(2026, 10, 1))
        try schedule("Netflix", 15_99, "Streaming Service", starting: day(2026, 10, 20))
        try schedule("Salary", 2_000_00, "Salary", .income, starting: day(2026, 10, 25))
        try schedule("Lend to Pasha", 100_00, "Loan", .debtLoan, starting: day(2026, 10, 15))

        let spent = try graph(.spent)
        let income = try graph(.income)

        #expect(spent.headline == Money(cents: 40_00))
        #expect(spent.expectedByMonthEnd == Money(cents: 55_99))
        #expect(income.headline == Money(cents: 1_000_00))
        #expect(income.expectedByMonthEnd == Money(cents: 3_000_00))
    }

    @Test(arguments: SpentOrIncome.allCases)
    func withNothingScheduledThereIsNoDottedLine(side: SpentOrIncome) throws {
        try record(-40_00, "Café", on: day(2026, 10, 3))
        try record(1_000_00, "Salary", .income, on: day(2026, 10, 1))

        let card = try graph(side)

        #expect(card.scheduledLine == nil)
        #expect(card.expectedByMonthEnd == nil)
    }

    // MARK: The popup on a day still to come

    @Test func aFutureDaysPopupListsWhatIsScheduledThatDayAndTheExpectedTotal() throws {
        try record(-40_00, "Café", on: day(2026, 10, 3))
        try schedule("Gym", 30_00, "Sports", starting: day(2026, 10, 20))
        try schedule("Netflix", 15_99, "Streaming Service", starting: day(2026, 10, 20))
        try schedule("Phone", 25_00, "Phone Bill", starting: day(2026, 10, 28))

        let spent = try graph(.spent)
        let twentieth = spent.popup(on: day(2026, 10, 20))
        let twentyFourth = spent.popup(on: day(2026, 10, 24))
        let twentyEighth = spent.popup(on: day(2026, 10, 28))

        #expect(twentieth.total == nil)
        #expect(Set(twentieth.scheduled) == [
            MonthGraphProjection.Item(name: "Gym", day: day(2026, 10, 20), amount: Money(cents: 30_00)),
            MonthGraphProjection.Item(name: "Netflix", day: day(2026, 10, 20), amount: Money(cents: 15_99)),
        ])
        #expect(twentieth.expected == Money(cents: 85_99))
        #expect(twentyFourth.scheduled.isEmpty)
        #expect(twentyFourth.expected == Money(cents: 85_99))
        #expect(twentyEighth.scheduled.map(\.name) == ["Phone"])
        #expect(twentyEighth.expected == Money(cents: 110_99))
    }

    /// September's spending gives the card an Average.
    @Test func aFutureDayBeforeAnythingIsScheduledShowsOnlyItsDateAndTheAverage() throws {
        try record(-31_00, "Café", on: day(2026, 9, 10))
        try record(-40_00, "Café", on: day(2026, 10, 3))
        try schedule("Gym", 30_00, "Sports", starting: day(2026, 10, 20))

        let popup = try graph(.spent).popup(on: day(2026, 10, 15))

        #expect(popup.day == day(2026, 10, 15))
        #expect(popup.comparison != nil)
        #expect(popup.total == nil)
        #expect(popup.scheduled.isEmpty)
        #expect(popup.expected == nil)
    }

    @Test func todaysPopupShowsTheTotalSoFarAndNothingScheduled() throws {
        try record(-40_00, "Café", on: day(2026, 10, 3))
        try schedule("Gym", 30_00, "Sports", starting: day(2026, 10, 20))

        let popup = try graph(.spent).popup(on: today)

        #expect(popup.total == Money(cents: 40_00))
        #expect(popup.scheduled.isEmpty)
        #expect(popup.expected == nil)
    }

    // MARK: An earlier month

    @Test(arguments: SpentOrIncome.allCases)
    func anEarlierMonthHasNoDottedLineAndNoExpectedByMonthEnd(side: SpentOrIncome) throws {
        try record(-40_00, "Café", on: day(2026, 9, 3))
        try record(1_000_00, "Salary", .income, on: day(2026, 9, 1))
        try schedule("Gym", 30_00, "Sports", starting: day(2026, 9, 20), preset: .weekly)
        try schedule("Salary", 2_000_00, "Salary", .income, starting: day(2026, 9, 25), preset: .weekly)

        let september = try graph(side, in: CalendarMonth(year: 2026, month: 9))
        let lastDay = september.popup(on: day(2026, 9, 30))

        #expect(september.scheduledLine == nil)
        #expect(september.expectedByMonthEnd == nil)
        #expect(lastDay.scheduled.isEmpty)
        #expect(lastDay.expected == nil)
        #expect(try graph(side).expectedByMonthEnd != nil)
    }
}
