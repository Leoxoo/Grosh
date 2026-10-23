import Foundation
import SwiftData
import Testing
@testable import Grosh

/// An Expense's Reimbursements go with it: to Recently Deleted, where they count in nothing, back when it is restored,
/// and out of the store for good when it is.
@MainActor
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
    private func reimbursedDinner() throws -> Transaction {
        let dinner = try store.record(-60_00, "Restaurants", on: day(2026, 10, 3))
        for cents in [20_00, 15_00] {
            try Reimbursement.add(ReimbursementDraft(amount: Money(cents: cents), day: today), to: dinner, in: context)
        }
        return dinner
    }

    private func storedReimbursementCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<Reimbursement>())
    }

    @Test func deletingAnExpenseKeepsItsReimbursementsWithItInRecentlyDeleted() throws {
        let dinner = try reimbursedDinner()

        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        #expect(dinner.isInRecentlyDeleted)
        #expect(dinner.orderedReimbursements.map(\.amountCents) == [20_00, 15_00])
        #expect(try storedReimbursementCount() == 2)
        #expect(try RecentlyDeleted(in: context).transactions == [dinner])
    }

    @Test func aDeletedExpenseAndItsReimbursementsCountInNoBalanceOrReport() throws {
        let dinner = try reimbursedDinner()

        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        #expect(checking.balance(asOf: today) == Money(cents: 0))
        #expect(dinner.countedAmount(otherIncome: try store.otherIncome()) == nil)
        #expect(try PeriodTotals(
            of: store.transactions(), in: .total, period: .month(CalendarMonth(today)), today: today,
            otherIncome: store.otherIncome()
        ) == PeriodTotals(income: Money(cents: 0), spent: Money(cents: 0)))
        #expect(try store.graph(.spent).headline == Money(cents: 0))
    }

    @Test func restoringAnExpenseBringsItsReimbursementsBack() throws {
        let dinner = try reimbursedDinner()
        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        try dinner.restore()

        #expect(!dinner.isInRecentlyDeleted)
        #expect(dinner.netCents == -25_00)
        #expect(checking.balance(asOf: today) == Money(cents: -25_00))
        #expect(dinner.countedAmount(otherIncome: try store.otherIncome())?.amount == Money(cents: 25_00))
        #expect(try store.graph(.spent).headline == Money(cents: 25_00))
    }

    @Test func deletingAnExpenseForeverRemovesItsReimbursementsToo() throws {
        let dinner = try reimbursedDinner()
        let kept = try reimbursedDinner()
        try dinner.delete(.onlySelected, in: context, at: deletedAt)

        try dinner.deleteForever(in: context)

        #expect(try storedReimbursementCount() == 2)
        #expect(kept.reimbursements?.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
    }

    @Test func theThirtyDayPurgeRemovesAnExpensesReimbursementsToo() throws {
        let dinner = try reimbursedDinner()
        try dinner.delete(.onlySelected, in: context, at: deletedAt)
        let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(thirtyDays - 1))
        #expect(try storedReimbursementCount() == 2)

        try RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(thirtyDays))
        #expect(try storedReimbursementCount() == 0)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 0)
    }

    @Test func emptyingTheBinRemovesReimbursementsOnlyOfWhatIsInIt() throws {
        let deleted = try reimbursedDinner()
        let kept = try reimbursedDinner()
        try deleted.delete(.onlySelected, in: context, at: deletedAt)

        try RecentlyDeleted.empty(in: context)

        #expect(try storedReimbursementCount() == 2)
        #expect(kept.netCents == -25_00)
    }

    @Test func deletingAWalletForeverRemovesTheReimbursementsOfItsExpenses() throws {
        let savings = Wallet(name: "Savings")
        context.insert(savings)
        let lunch = try store.record(-30_00, "Restaurants", on: day(2026, 10, 4), in: savings)
        try Reimbursement.add(ReimbursementDraft(amount: Money(cents: 10_00), day: today), to: lunch, in: context)
        try reimbursedDinner()

        try savings.delete(at: deletedAt)
        #expect(lunch.orderedReimbursements.count == 1)
        #expect(try storedReimbursementCount() == 3)

        try savings.deleteForever(in: context)

        #expect(try storedReimbursementCount() == 2)
    }

    @Test func deletingAReimbursementDoesNotDeleteItsExpense() throws {
        let dinner = try reimbursedDinner()

        try #require(dinner.orderedReimbursements.first { $0.amountCents == 20_00 }).delete()

        #expect(!dinner.isInRecentlyDeleted)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 1)
        #expect(dinner.netCents == -45_00)
    }
}
