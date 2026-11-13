import Foundation
import SwiftData
import Testing
@testable import Grosh

/// An Expense's Reimbursements go with it: to Recently Deleted, where they count in nothing, back when it is restored,
/// and out of the store for good when it is.
@MainActor
@Suite(.namedInTheLog)
struct ReimbursementRecentlyDeletedTests {
    private let store: MonthGraphFixture
    private var context: ModelContext { store.context }
    private var checking: Wallet { store.checking }
    private var today: CalendarDay { store.today }
    private let deletedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    init() throws {
        store = try MonthGraphFixture()
    }

    /// A $60 dinner on the 3rd with $20 and $15 of it paid back.
    @discardableResult
    private func dinnerPaidBackTwice() throws -> Transaction {
        let dinner = try store.recordDinner()
        for cents in [20_00, 15_00] {
            try context.payBack(cents, on: today, to: dinner)
        }
        return dinner
    }

    private func storedReimbursementCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Reimbursement>())
    }

    @Test func deletingAnExpenseKeepsItsReimbursementsWithItInRecentlyDeleted() throws {
        let dinner = try dinnerPaidBackTwice()

        try dinner.delete(.onlySelected, at: deletedAt)

        #expect(dinner.isInRecentlyDeleted)
        #expect(dinner.orderedReimbursements.map(\.amountCents) == [20_00, 15_00])
        #expect(try storedReimbursementCount() == 2)
        #expect(try RecentlyDeleted(in: context).transactions == [dinner])
    }

    @Test func aDeletedExpenseAndItsReimbursementsCountInNoBalanceOrReport() throws {
        let dinner = try dinnerPaidBackTwice()

        try dinner.delete(.onlySelected, at: deletedAt)

        #expect(walletBalance(checking, asOf: today) == Money(cents: 0))
        #expect(dinner.countedAmount(currencyCode: "USD", otherIncome: try store.otherIncome()) == nil)
        #expect(try store.totals() == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
        #expect(try store.graph(.spent).headline == Money(cents: 0))
    }

    @Test func restoringAnExpenseBringsItsReimbursementsBack() throws {
        let dinner = try dinnerPaidBackTwice()
        try dinner.delete(.onlySelected, at: deletedAt)

        try dinner.restore()

        #expect(!dinner.isInRecentlyDeleted)
        #expect(dinner.netCents == -25_00)
        #expect(walletBalance(checking, asOf: today) == Money(cents: -25_00))
        #expect(dinner.countedAmount(currencyCode: "USD", otherIncome: try store.otherIncome())?.amount == Money(cents: 25_00))
        #expect(try store.graph(.spent).headline == Money(cents: 25_00))
    }

    @Test func deletingAnExpenseForeverRemovesItsReimbursementsToo() throws {
        let dinner = try dinnerPaidBackTwice()
        let kept = try dinnerPaidBackTwice()
        try dinner.delete(.onlySelected, at: deletedAt)

        try dinner.deleteForever()

        #expect(try storedReimbursementCount() == 2)
        #expect(kept.reimbursements?.count == 2)
        #expect(try context.transactionCount() == 1)
    }

    @Test func theThirtyDayPurgeRemovesAnExpensesReimbursementsToo() throws {
        let dinner = try dinnerPaidBackTwice()
        try dinner.delete(.onlySelected, at: deletedAt)
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(thirtyDays - 1))
        #expect(try storedReimbursementCount() == 2)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(thirtyDays))
        #expect(try storedReimbursementCount() == 0)
        #expect(try context.transactionCount() == 0)
    }

    @Test func emptyingTheBinRemovesReimbursementsOnlyOfWhatIsInIt() throws {
        let deleted = try dinnerPaidBackTwice()
        let kept = try dinnerPaidBackTwice()
        try deleted.delete(.onlySelected, at: deletedAt)

        try RecentlyDeleted.empty(in: context)

        #expect(try storedReimbursementCount() == 2)
        #expect(kept.netCents == -25_00)
    }

    @Test func deletingAWalletForeverRemovesTheReimbursementsOfItsExpenses() throws {
        let savings = context.addWallet("Savings")
        let lunch = try store.record(-30_00, "Restaurants", on: day(2026, 10, 4), in: savings)
        try context.payBack(10_00, on: today, to: lunch)
        try dinnerPaidBackTwice()

        try savings.delete(today: CalendarDay(deletedAt), at: deletedAt)
        #expect(lunch.orderedReimbursements.count == 1)
        #expect(try storedReimbursementCount() == 3)

        try savings.deleteForever()

        #expect(try storedReimbursementCount() == 2)
    }

    @Test func deletingAReimbursementDoesNotDeleteItsExpense() throws {
        let dinner = try dinnerPaidBackTwice()

        // The $20, so the $60 dinner keeps the $15 paid back.
        try #require(dinner.orderedReimbursements.first { $0.amountCents == 20_00 }).delete()

        #expect(!dinner.isInRecentlyDeleted)
        #expect(try context.transactionCount() == 1)
        #expect(dinner.netCents == -45_00)
    }
}
